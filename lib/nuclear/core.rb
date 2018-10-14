# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'


import('./ext/fiber')

FiberPool   = import('./core/fiber_pool')
CancelScope = import('./core/cancel_scope')
Task        = import('./core/task')
Nexus       = import('./core/nexus')

module ::Kernel
  def id
    "#{self.class.to_s[/[^:]+$/]}:#{object_id.to_s[-3..-1]}"
  end

  # temporary, but very useful debugging facility, can be used in two ways:
  #
  #     # print current method name and its arguments
  #     _p binding
  #     # => my_method("hello", "world")
  #
  #     # print arbitrary method name and arguments
  #     _p :my_method, x, y
  def _p(*args)
    if (args.size == 1) && args.first.is_a?(Binding)
      caller_binding = args.first
      caller_name = caller[0][/`.*'/][1..-2]
      method = caller_binding.receiver.method(caller_name)
      arguments = method.parameters.map do |_, n|
        n && caller_binding.local_variable_get(n)
      end
      _p(method.name, *arguments)
    else
      sym, *args = *args
      STDOUT.puts "%s(%s)" % [sym, args.map(&:inspect).join(', ')]
    end
  end

  def async(sym = nil, &block)
    if sym
      async_decorate(sym)
    else
      async_task(&block)
    end
  end

  def async!(&block)
    FiberPool.invoke do |fiber|
      async_task(&block).call
    end
  end

  def async_task(&block)
    proc do |&override_block|
      calling_fiber = Fiber.current
      task_fiber = nil
      done = nil
      EV::Timer.new(0, 0) do
        FiberPool.invoke do |fiber|
          begin
            task_fiber = fiber
            result = (override_block || block).()
            task_fiber = nil
            calling_fiber.resume(result)
          rescue Exception => e
            task_fiber = nil
            calling_fiber&.resume(e)
          end
        end
      end
      begin
        Fiber.yield_and_raise_error
      rescue Cancelled, MoveOn => e
        calling_fiber = nil
        task_fiber&.resume(e)
        raise e
      end
    end
  end

  def async_decorate(sym)
    sync_sym = :"sync_#{sym}"
    receiver = is_a?(Class) ? self : singleton_class
    receiver.alias_method(sync_sym, sym)
    receiver.define_method(sym) do |*args, &block|
      async_task { send(sync_sym, *args, &block) }
    end
  end

  def await(task, &block)
    return nil if Fiber.current.cancelled

    if task && block
      task.call(&block)
    else
      (task || block).call
    end
  end

  def cancel_after(timeout, &block)
    c = CancelScope.new(timeout: timeout)
    c.run(&block)
  end

  def nexus(tasks = nil, &block)
    return Nexus.new(tasks, &block).to_proc

    # Nexus.new(tasks, &block)
  end

  def move_on_after(timeout, &block)
    c = CancelScope.new(timeout: timeout, mode: :move_on)
    c.run(&block)
  end
end

# Core module, containing async and reactor methods
module Core
  def self.sleep(duration)
    proc do
      begin
        fiber = Fiber.current
        timer = EV::Timer.new(duration, 0) { fiber.resume duration }
        Fiber.yield_and_raise_error
      ensure
        timer&.stop
      end
    end
  end

  def self.pulse(freq, &block)
    fiber = Fiber.current
    timer = EV::Timer.new(freq, freq) { fiber.resume freq }
    proc do
      begin
        Fiber.yield_and_raise_error
        # Exception === result ? raise(result) : result
      rescue Exception => e
        timer.stop
        raise e
      end
    end
    # Task.new(start: true) do |t|
    #   timer = EV::Timer.new(freq, freq) { t.resolve(freq) }
    #   t.on_cancel { timer.stop }
    # end
  end

  def self.trap(sig, &cb)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &cb)
  end
end

def auto_run
  return if @auto_ran
  @auto_ran = true
  
  return if $!
  Core.trap(:int) { puts; EV.break }
  EV.unref # undo ref count increment caused by signal trap
  EV.run
end

at_exit { auto_run }