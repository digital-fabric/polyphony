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

  def acquire
    resource = wait
    yield resource
  ensure
    @available << resource if resource
    dequeue
  end

  def wait
    fiber = Fiber.current
    @waiting << fiber
    dequeue
    suspend
  ensure
    @waiting.delete(fiber)
  end

  def dequeue
    return unless (resource = from_stock)
    EV.next_tick { @waiting[0]&.transfer(resource) }
  end

  def from_stock
    @available.shift || (@count < @limit && allocate)
  end

  # Allocates a resource
  # @return [any] allocated resource
  def allocate
    @count += 1
    @allocator.()
  end

  def preheat!
    (@limit - @count).times { @available << from_stock }
  end
end
