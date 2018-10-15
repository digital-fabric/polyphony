# frozen_string_literal: true

export :set_fiber_local_resource

# Proc extensions
class ::Proc
  attr_accessor :async
end

# Fiber extensions
class ::Fiber
  # yields control of fiber, raising error if resumed value is an exception
  # @param value [any] value to yield
  # @return [any] resumed value if not an exception
  def self.yield_and_raise_error(value = nil)
    result = self.yield(value)
    result.is_a?(Exception) ? raise(result) : result
  end

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
