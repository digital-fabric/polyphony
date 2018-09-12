# frozen_string_literal: true

export_default :Pool

FiberExt = import('./ext/fiber')

# Implements a limited resource pool
class Pool
  # Initializes a new resource pool
  # @param opts [Hash] options
  # @param &block [Proc] allocator block
  def initialize(opts, &block)
    @allocator = block

    @resources = []
    @queue = []

    @limit = opts[:limit] || 4
    @count = 0
  end

  MSG_ASYNC_USE = 'use can only be called inside async block'

  # Adds the given block to the task queue. The block will be run once a
  # resource is available
  def use(&block)
    raise MSG_ASYNC_USE unless Fiber.current.async?

    @queue << block
    pull_task_from_queue
  end

  # Uses resource from pool, setting it as fiber-local value
  # @param key [Symbol] resource name
  # @return [void]
  def use_as(key, &block)
    use { |resource| with_fiber_local(key, resource, &block) }
  end

  # Pull a task from the queue and run it, provided a resource is available
  # @return [void]
  def pull_task_from_queue
    return if @resources.empty? && @count == @limit

    resource = @resources.shift || allocate

    run_task(resource, &@queue.shift)
  end

  # Runs a task with the given resource, releasing it once the task is done
  # @param resource [any]
  # @return [void]
  def run_task(resource)
    yield resource
  ensure
    release(resource)
  end

  # Allocates a resource
  # @return [any] allocated resource
  def allocate
    @count += 1
    @allocator.()
  end

  # Releases a resource back to the pool, running the next task in the queue
  # if the queue is not empty
  # @param resource [any]
  # @return [void]
  def release(resource)
    @resources << resource
    pull_task_from_queue unless @queue.empty?
  end

  # Runs the given block, setting a fiber-local value for use as global value
  # @param key [Symbol] resource name
  # @param resource [any]
  # @return [void]
  def with_fiber_local(key, resource)
    set_fiber_local(key, resource)
    yield
  ensure
    set_fiber_local(key, nil)
  end

  # Set fiber local value
  # @param key [Symbol] resource name
  # @param value [any]
  # @return [void]
  def set_fiber_local(key, value)
    FiberExt.set_fiber_local_resource(key, value)
  end
end
