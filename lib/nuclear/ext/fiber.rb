export :set_fiber_local_resource

# Fiber extensions
class ::Fiber
  # Returns true if fiber is marked as async
  # @return [Boolean] is fiber async
  def async?
    @async
  end

  # Marks the fiber as async
  # @return [void]
  def async!
    @async = true
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
    @locals[key]  = value
  end
end

  # Sets a fiber-local value, adding a global accessor to Object. The value
  # will be accessible using the given key, e.g.:
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