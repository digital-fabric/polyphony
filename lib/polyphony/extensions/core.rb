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
  attr_accessor :__calling_fiber__
  attr_writer :__caller__
  attr_writer :cancelled
  attr_accessor :coprocess, :scheduled_value

  class << self
    alias_method :orig_new, :new
    def new(&block)
      calling_fiber = Fiber.current
      fiber_caller = caller
      fiber = orig_new do |v|
        block.call(v)
      ensure
        $__reactor_fiber__.safe_transfer if $__reactor_fiber__.alive?
      end
      fiber.__calling_fiber__ = calling_fiber
      fiber.__caller__ = fiber_caller
      fiber
    end

    def root
      @root_fiber
    end

    def set_root_fiber
      @root_fiber = current
    end
    end

  def caller
    @__caller__ ||= []
    if @__calling_fiber__
      @__caller__ + @__calling_fiber__.caller
    else
      @__caller__
    end
  end

  def cancelled?
    @cancelled
  end

  # Associate a (pseudo-)coprocess with the root fiber
  current.coprocess = Coprocess.new(current)
  set_root_fiber
end

# Exeption overrides
class ::Exception
  class << self
    attr_accessor :__disable_sanitized_backtrace__
  end

  alias_method :orig_initialize, :initialize

  def initialize(*args)
    @__raising_fiber__ = Fiber.current
    orig_initialize(*args)
  end

  alias_method_once :orig_backtrace, :backtrace
  def backtrace
    unless @first_backtrace_call
      @first_backtrace_call = true
      return orig_backtrace
    end

    if @__raising_fiber__
      backtrace = orig_backtrace || []
      sanitize(backtrace + @__raising_fiber__.caller)
    else
      sanitize(orig_backtrace)
    end
  end

  POLYPHONY_DIR = File.expand_path(File.join(__dir__, '..'))

  def sanitize(backtrace)
    return backtrace if ::Exception.__disable_sanitized_backtrace__

    backtrace.reject { |l| l[POLYPHONY_DIR] }
  end
end

# Pulser abstraction for recurring operations
class Pulser
  def initialize(freq)
    fiber = Fiber.current
    @timer = Gyro::Timer.new(freq, freq)
  end

  def await
    @timer.await
  end

  def stop
    @timer.stop
  end
end

# Overrides for Process
module ::Process
  def self.detach(pid)
    spin do
      Gyro::Child.new(pid).await
    end.tap { |coproc| coproc.define_singleton_method(:pid) { pid } }
  end
end

# Kernel extensions (methods available to all objects / call sites)
module ::Kernel
  def after(interval, &block)
    Gyro::Timer.new(interval, 0).start(&block)
  end

  def cancel_after(duration, &block)
    CancelScope.new(timeout: duration, mode: :cancel).(&block)
  end

  def spin(&block)
    Coprocess.new(&block).run
  end

  def spin_loop(&block)
    spin { loop(&block) }
  end

  def every(freq, &block)
    Gyro::Timer.new(freq, freq).start(&block)
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
    timer = Gyro::Timer.new(duration, 0)
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
    # $stdout.orig_puts '*' * 60
    # $stdout.orig_puts caller.join("\n")
    Open3.popen3(cmd) do |i, o, e, _t|
      i.close
      while (l = e.readpartial(8192))
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
  rescue Exception => e
    calling_fiber.transfer(e)
  end

  alias_method :orig_gets, :gets
  def gets(*_args)
    return $stdin.gets if ARGV.empty?

    @gets_fiber ||= Fiber.new(&ARGV_GETS_LOOP)
    return @gets_fiber.safe_transfer(Fiber.current) if @gets_fiber.alive?

    nil
  end

  alias_method :orig_system, :system
  def system(*args)
    Open3.popen2(*args) do |i, o, _t|
      i.close
      while (l = o.readpartial(8192))
        $stdout << l
      end
    end
    true
  rescue SystemCallError
    nil
  end
end

# Override Timeout to use cancel scope
module ::Timeout
  def self.timeout(sec, klass = nil, message = nil, &block)
    cancel_after(sec, &block)
  rescue Exceptions::Cancel => e
    error = klass ? klass.new(message) : ::Timeout::Error.new
    error.set_backtrace(e.backtrace)
    raise error
  end
end
