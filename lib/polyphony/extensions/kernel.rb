# frozen_string_literal: true

require 'open3'

module Polyphony
  # Intercepts calls to #trap
  module TrapInterceptor
    # Installs a signal handler. If a block is given (or the command parameter
    # is a Proc or a callable), it is executed inside an out-of-band,
    # prioritized fiber.
    #
    # If the command is the string “IGNORE” or “SIG_IGN”, the signal will be
    # ignored. If the command is “DEFAULT” or “SIG_DFL”, the Ruby’s default
    # handler will be invoked. If the command is “EXIT”, the script will be
    # terminated by the signal. If the command is “SYSTEM_DEFAULT”, the
    # operating system’s default handler will be invoked. Otherwise, the given
    # command or block will be run. The special signal name “EXIT” or signal
    # number zero will be invoked just prior to program termination.
    #
    # trap returns the previous handler for the given signal.
    #
    # @param sig [String, Symbol, Integer] signal name or number
    # @param command [String, Proc] command to perform
    def trap(sig, command = nil, &block)
      return super(sig, command) if command.is_a? String

      block = command if !block && command.respond_to?(:call)

      # The signal trap can be invoked at any time, including while the system
      # backend is blocking while polling for events. In order to deal with this
      # correctly, we run the signal handler code in an out-of-band, priority
      # scheduled fiber, that will pass any uncaught exception (including
      # SystemExit and Interrupt) to the main thread's main fiber. See also
      # `Fiber#schedule_priority_oob_fiber`.
      super(sig) do
        Fiber.schedule_priority_oob_fiber(&block)
      end
    end
  end
end

# Kernel extensions (methods available to all objects / call sites)
module ::Kernel
  # @!visibility private
  alias_method :orig_sleep, :sleep

  # @!visibility private
  alias_method :orig_backtick, :`

  # @!visibility private
  def `(cmd)
    Open3.popen3(cmd) do |i, o, e, _t|
      i.close
      err = e.read
      $stderr << err if err
      o.read || ''
    end
  end

  # @!visibility private
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

  # @!visibility private
  alias_method :orig_gets, :gets

  # Reads a single line from STDIN
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

  # @!visibility private
  alias_method :orig_p, :p

  # @!visibility private
  def p(*args)
    strs = args.inject([]) do |m, a|
      m << a.inspect << "\n"
    end
    $stdout.write(*strs)
    args.size == 1 ? args.first : args
  end

  # @!visibility private
  alias_method :orig_system, :system

  # @!visibility private
  def system(*args)
    Kernel.system(*args)
  end

  class << self
    # @!visibility private
    alias_method :orig_trap, :trap

    # @!visibility private
    alias_method :orig_system, :system

    # @!visibility private
    def system(*args)
      waiter = nil
      Open3.popen2(*args) do |i, o, t|
        waiter = t
        i.close
        pipe_to_eof(o, $stdout)
      end
      waiter.value.success?
    rescue SystemCallError
      nil
    end
  end

  # @!visibility private
  alias_method :orig_trap, :trap

  prepend Polyphony::TrapInterceptor

  class << self
    prepend Polyphony::TrapInterceptor
  end

  # # @!visibility private
  # def trap(sig, command = nil, &block)
  #   return orig_trap(sig, command) if command.is_a? String

  #   block = command if !block && command.respond_to?(:call)

  #   # The signal trap can be invoked at any time, including while the system
  #   # backend is blocking while polling for events. In order to deal with this
  #   # correctly, we run the signal handler code in an out-of-band, priority
  #   # scheduled fiber, that will pass any uncaught exception (including
  #   # SystemExit and Interrupt) to the main thread's main fiber. See also
  #   # `Fiber#schedule_priority_oob_fiber`.
  #   orig_trap(sig) do
  #     Fiber.schedule_priority_oob_fiber(&block)
  #   end
  # end

  private

  # @!visibility private
  def pipe_to_eof(src, dest)
    src.read_loop { |data| dest << data }
  end
end

module ::Process
  class << self
    prepend Polyphony::TrapInterceptor
  end
end
