# frozen_string_literal: true

export :set_fiber_local_resource

Async       = import('./async')
CancelScope = import('./cancel_scope')
FiberPool   = import('./fiber_pool')
Nexus       = import('./nexus')

# Kernel extensions (methods available to all objects)
module ::Kernel
  def async(sym = nil, &block)
    if sym
      Async.async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Async.async_task(&block)
    end
  end

  def spawn(&block)
    EV.next_tick do
      if block.async
        yield
      else
        FiberPool.spawn(&block)
      end
    end
  end

  def await(proc, &block)
    return nil if Fiber.current.cancelled

    Async.call_proc_with_optional_block(proc, block)
  end

  def cancel_after(timeout, &block)
    CancelScope.new(timeout: timeout).run(&block)
  end

  def cancel_scope(&block)
    CancelScope.new.run(&block)
  end

  def move_on_after(timeout, &block)
    CancelScope.new(timeout: timeout, mode: :move_on).run(&block)
  end

  def nexus(tasks = nil, &block)
    Nexus.new(tasks, &block).to_proc
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
