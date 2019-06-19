# frozen_string_literal: true

require 'fiber'
require 'timeout'
require 'open3'

CancelScope = import('../core/cancel_scope')
Coprocess   = import('../core/coprocess')
Exceptions  = import('../core/exceptions')
Supervisor  = import('../core/supervisor')
Throttler   = import('../core/throttler')

# Fiber extensions
class ::Fiber
  attr_writer :cancelled
  attr_accessor :next_job, :coprocess

  def cancelled?
    @cancelled
  end

  def schedule(value = nil)
    EV.schedule_fiber(self, value)
  end

  # Associate a (pseudo-)coprocess with the main fiber
  current.coprocess = Coprocess.new(current)
  
  @@main_fiber = current

  def self.main
    @@main_fiber
  end
end

class ::Exception
  SANITIZE_RE = /lib\/polyphony/.freeze
  SANITIZE_PROC = proc  { |l| l !~ SANITIZE_RE }

  def cleanup_backtrace(caller = nil)
    combined = caller ? backtrace + caller : backtrace
    set_backtrace(combined.select(&SANITIZE_PROC))
  end
end

class Pulser
  def initialize(freq)
    fiber = Fiber.current
    @timer = EV::Timer.new(freq, freq)
    @timer.start { fiber.transfer freq }
  end

  def await
    suspend
  rescue Exception => e
    @timer.stop
    raise e
  end

  def stop
    @timer.stop
  end
end

module ::Process
  def self.detach(pid)
    spin {
      EV::Child.new(pid).await
    }.tap { |coproc| coproc.define_singleton_method(:pid) { pid } }
  end
end

# Kernel extensions (methods available to all objects)
module ::Kernel
  def after(duration, &block)
    EV::Timer.new(freq, 0).start(&block)
  end

  def async(sym = nil, &block)
    if sym
      async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Coprocess.new(&block)
    end
  end

  # Converts a regular method into an async method, i.e. a method that returns a
  # proc that eventually executes the original code.
  # @param receiver [Object] object receiving the method call
  # @param sym [Symbol] method name
  # @return [void]
  def async_decorate(receiver, sym)
    sync_sym = :"sync_#{sym}"
    receiver.alias_method(sync_sym, sym)
    receiver.class_eval("def #{sym}(*args, &block); Coprocess.new { send(#{sync_sym.inspect}, *args, &block) }; end")
  end

  def cancel_after(duration, &block)
    CancelScope.new(timeout: duration, mode: :cancel).(&block)
  end

  def spin(proc = nil, &block)
    if proc.is_a?(Coprocess)
      proc.run
    else
      Coprocess.new(&(block || proc)).run
    end
  end

  def spin_loop(&block)
    spin { loop(&block) }
  end

  def every(freq, &block)
    EV::Timer.new(freq, freq).start(&block)
  end

  def move_on_after(duration, &block)
    CancelScope.new(timeout: duration).(&block)
  end

  def pulse(freq)
    Pulser.new(freq)
  end

  def receive
    Fiber.current.coprocess.receive
  end

  alias_method :sync_sleep, :sleep
  def sleep(duration)
    timer = EV::Timer.new(duration, 0)
    timer.await
  ensure
    timer.stop
  end

  def supervise(&block)
    Supervisor.new.await(&block)
  end

  def throttled_loop(rate, count: nil, &block)
    throttler = Throttler.new(rate)
    if count
      count.times { throttler.(&block) }
    else
      loop { throttler.(&block) }
    end
  end

  def throttle(rate)
    Throttler.new(rate)
  end

  def timeout(duration, opts = {}, &block)
    CancelScope.new(**opts, timeout: duration).(&block)
  end

  # patches

  alias_method :orig_backtick, :`
  def `(cmd)
    Open3.popen3(cmd) do |i, o, e, t|
      i.close
      while (l = e.readpartial(8192) rescue nil)
        $stderr << l
      end
      o.read
    end
  end

  ARGV_GETS_LOOP = proc do |calling_fiber|
    ARGV.each do |fn|
      File.open(fn, 'r') do |f|
        while (line = f.gets)
          calling_fiber = calling_fiber.transfer(line)
        end
      end
    end
  rescue => e
    calling_fiber.transfer(e)
  end

  alias_method :orig_gets, :gets
  def gets(*args)
    return $stdin.gets if ARGV.empty?
    
    @gets_fiber ||= Fiber.new(&ARGV_GETS_LOOP)
    if @gets_fiber.alive?
      @gets_fiber.safe_transfer(Fiber.current)
    else
      nil
    end
  end

  alias_method :orig_system, :system
  def system(*args)
    Open3.popen2(*args) do |i, o, t|
      i.close
      while (l = o.readpartial(8192))
        $stdout << l
      end
    end
    true
  rescue SystemCallError => e
    nil
  end
end

module ::Timeout
  def self.timeout(sec, klass = nil, message = nil, &block)
    cancel_after(sec, &block)
  rescue Exceptions::Cancel => e
    error = klass ? klass.new(message) : ::Timeout::Error.new
    error.set_backtrace(e.backtrace)
    raise error
  end
end