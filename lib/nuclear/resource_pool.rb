# frozen_string_literal: true

export_default :Pool

FiberExt = import('./ext/fiber')

class Pool
  def initialize(opts, &block)
    @allocator = block
    
    @resources = []
    @queue = []

    @limit = opts[:limit] || 4
    @count = 0
  end

  def use(&block)
    unless Fiber.current.async?
      raise RuntimeError, 'use can only be called inside async block'
    end

    @queue << block
    pull_from_queue
  end

  def use_as(key, &block)
    use { |resource| with_fiber_local(key, resource, &block) }
  end

  def pull_from_queue
    return if @resources.empty? && @count == @limit

    resource = @resources.shift || allocate

    run_task(resource, &@queue.shift)
  end

  def run_task(resource, &block)
    block.(resource)
  ensure
    release(resource)
  end

  def allocate
    @count += 1
    @allocator.()
  end

  def release(resource)
    @resources << resource
    pull_from_queue unless @queue.empty?
  end

  def with_fiber_local(key, resource, &block)
    set_fiber_local(key, resource)
    block.()
  ensure
    set_fiber_local(key, nil)
  end

  def set_fiber_local(key, value)
    FiberExt.set_fiber_local_resource(key, value)
  end
end
