# frozen_string_literal: true

require 'fiber'
require 'timeout'
require 'open3'

require_relative '../core/exceptions'

# Exeption overrides
class ::Exception
  class << self
    attr_accessor :__disable_sanitized_backtrace__
  end

  attr_accessor :source_fiber, :raising_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args)
    @raising_fiber = Fiber.current
    orig_initialize(*args)
  end

  alias_method :orig_backtrace, :backtrace
  def backtrace
    unless @backtrace_called
      @backtrace_called = true
      return orig_backtrace
    end

    sanitized_backtrace
  end

  def sanitized_backtrace
    return sanitize(orig_backtrace) unless @raising_fiber

    backtrace = orig_backtrace || []
    sanitize(backtrace + @raising_fiber.caller)
  end

  POLYPHONY_DIR = File.expand_path(File.join(__dir__, '..'))

  def sanitize(backtrace)
    return backtrace if ::Exception.__disable_sanitized_backtrace__

    backtrace.reject { |l| l[POLYPHONY_DIR] }
  end

  def invoke
    Kernel.raise(self)
  end
end

# Overrides for Process
module ::Process
  class << self
    alias_method :orig_detach, :detach
    def detach(pid)
      fiber = spin { Polyphony.backend_waitpid(pid) }
      fiber.define_singleton_method(:pid) { pid }
      fiber
    end

    alias_method :orig_daemon, :daemon
    def daemon(*args)
      orig_daemon(*args)
      Polyphony.original_pid = Process.pid
    end
  end
end

# Kernel extensions (methods available to all objects / call sites)
module ::Kernel
  alias_method :orig_sleep, :sleep

  alias_method :orig_backtick, :`
  def `(cmd)
    Open3.popen3(cmd) do |i, o, e, _t|
      i.close
      err = e.read
      $stderr << err if err
      o.read || ''
    end
  end

  ARGV_GETS_LOOP = proc do |calling_fiber|
    while (fn = ARGV.shift)
      File.open(fn, 'r') do |f|
        while (line = f.gets)
          calling_fiber = calling_fiber.transfer(line)
        end
      end
    end
    nil
  rescue Exception => e
    calling_fiber.transfer(e)
  end

  alias_method :orig_gets, :gets
  def gets(*_args)
    if !ARGV.empty? || @gets_fiber
      @gets_fiber ||= Fiber.new(&ARGV_GETS_LOOP)
      @gets_fiber.thread = Thread.current
      result = @gets_fiber.alive? && @gets_fiber.safe_transfer(Fiber.current)
      return result if result

      @gets_fiber = nil
    end

    $stdin.gets
  end

  alias_method :orig_p, :p
  def p(*args)
    strs = args.inject([]) do |m, a|
      m << a.inspect << "\n"
    end
    STDOUT.write(*strs)
    args.size == 1 ? args.first : args
  end

  alias_method :orig_system, :system
  def system(*args)
    Kernel.system(*args)
  end

  class << self
    alias_method :orig_system, :system
    def system(*args)
      waiter = nil
      Open3.popen2(*args) do |i, o, t|
        waiter = t
        i.close
        pipe_to_eof(o, $stdout)
      end
      waiter.await.last == 0
    rescue SystemCallError
      nil
    end
  end

  def pipe_to_eof(src, dest)
    src.read_loop { |data| dest << data }
  end

  alias_method :orig_trap, :trap
  def trap(sig, command = nil, &block)
    return orig_trap(sig, command) if command.is_a? String

    block = command if !block && command.respond_to?(:call)

    # The signal trap can be invoked at any time, including while the system
    # backend is blocking while polling for events. In order to deal with this
    # correctly, we run the signal handler code in an out-of-band, priority
    # scheduled fiber, that will pass any uncaught exception (including
    # SystemExit and Interrupt) to the main thread's main fiber. See also
    # `Fiber#schedule_priority_oob_fiber`.
    orig_trap(sig) do
      Fiber.schedule_priority_oob_fiber(&block)
    end
  end
end

# Override Timeout to use cancel scope
module ::Timeout
  def self.timeout(sec, klass = Timeout::Error, message = 'execution expired', &block)
    cancel_after(sec, with_exception: [klass, message], &block)
  end
end
