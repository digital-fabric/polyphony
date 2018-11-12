# frozen_string_literal: true

export :set_fiber_local_resource

Async       = import('./async')
CancelScope = import('./cancel_scope')
Exceptions  = import('./exceptions')
FiberPool   = import('./fiber_pool')
Supervisor  = import('./supervisor')
Task        = import('./task')

# Kernel extensions (methods available to all objects)
module ::Kernel
  def async(sym = nil, &block)
    if sym
      Async.async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Task.new(&block)
    end
  end

  def spawn(task = nil, &block)
    task.is_a?(Task) ? task.start : Task.new(&(block || task)).start
  end

  def await(task, &block)
    return nil if Fiber.current.cancelled

    task.is_a?(Task) ?
      task.await(&block) : Async.call_proc_with_optional_block(task, block)
  rescue Exceptions::TaskInterrupted => e
    if task.is_a?(Task) && task.running?
      task.interrupt(e)
    else
      raise e
    end
  end

  def cancel_after(timeout, &block)
    CancelScope.new(timeout: timeout).run(&block)
  end

  def cancel_scope(&block)
    CancelScope.new.run(&block)
  end

  def stop_after(timeout, &block)
    CancelScope.new(timeout: timeout, mode: :stop).run(&block)
  end
  alias_method :move_on_after, :stop_after

  def supervise(&block)
    Supervisor.new(&block)
  end

  # yields from current fiber, raising error if resumed value is an exception
  # @return [any] resumed value if not an exception
  def suspend
    result = Fiber.yield
    result.is_a?(Exception) ? raise(result) : result
  end

  def resume_on_next_tick
    fiber = Fiber.current
    EV.next_tick { fiber.resume }
    Fiber.yield
  end

  def after(duration, &block)
    EV::Timer.new(freq, 0).start(&block)
  end

  def every(freq, &block)
    EV::Timer.new(freq, freq).start(&block)
  end

  alias_method :sync_sleep, :sleep 

  def sleep(duration)
    proc do
      timer = EV::Timer.new(duration, 0)
      timer.await
    ensure
      timer.stop
    end
  end

  def pulse(freq)
    fiber = Fiber.current
    timer = EV::Timer.new(freq, freq)
    timer.start { fiber.resume freq }
    proc do
      suspend
    rescue Exception => e
      timer.stop
      raise e
    end
  end
end

# Proc extensions
class ::Proc
  attr_accessor :async
end

# Fiber extensions
class ::Fiber
  attr_accessor :cancelled
  attr_writer   :root

  # Returns true if fiber is root fiber
  # @return [boolean]
  def root?
    @root
  end

  # Returns fiber-local value
  # @param key [Symbol]
  # @return [any]
  def [](key)
    @locals ||= {}
    @locals[key]
  end

  # Sets fiber-local value
  # @param key [Symbol]
  # @param value [any]
  # @return [void]
  def []=(key, value)
    @locals ||= {}
    @locals[key] = value
  end
end

Fiber.current.root = true

# Sets a fiber-local value, adding a global accessor to Object. The value will
# be accessible using the given key, e.g.:
#
#     FiberExt = import('./nuclear/ext/fiber')
#     async do
#       FiberExt.set_fiber_local_resource(:my_db, db_connection)
#       ...
#       result = await my_db.query(sql)
#     end
#
# @param key [Symbol]
# @param value [any]
# @return [void]
def set_fiber_local_resource(key, value)
  unless Object.respond_to?(key)
    Object.define_method(key) { Fiber.current[key] }
  end
  Fiber.current[key] = value
end
