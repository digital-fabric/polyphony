# frozen_string_literal: true

export_default :ResourcePool

# Implements a limited resource pool
class ResourcePool
  # Initializes a new resource pool
  # @param opts [Hash] options
  # @param &block [Proc] allocator block
  def initialize(opts, &block)
    @allocator = block

    @available = []
    @waiting = []

    @limit = opts[:limit] || 4
    @count = 0
  end

  def acquire(&block)
    resource = wait
    block.(resource)
  ensure
    @available << resource
    dequeue
  end

  def wait
    fiber = Fiber.current
    @waiting << fiber
    dequeue
    return Fiber.yield_and_raise_error
  ensure
    @waiting.delete(fiber)
  end

  def dequeue
    if resource = get_from_stock
      EV.next_tick { @waiting[0]&.resume(resource) }
    end
  end

  def get_from_stock
    @available.shift || (@count < @limit && allocate)
  end

  # Allocates a resource
  # @return [any] allocated resource
  def allocate
    @count += 1
    @allocator.()
  end
end