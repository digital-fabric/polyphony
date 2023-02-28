# frozen_string_literal: true

require 'open3'

# Kernel extensions (methods available to all objects / call sites)
module ::Kernel
  alias_method :orig_sleep, :sleep

  alias_method :orig_backtick, :`

  # TODO: add docs to all methods in this file
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

  private

  # :no-doc:
  def pipe_to_eof(src, dest)
    src.read_loop { |data| dest << data }
  end
end
