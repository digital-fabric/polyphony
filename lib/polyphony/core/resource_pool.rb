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
    dequeue unless @waiting.empty?
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

    defer { @waiting[0]&.transfer(resource) }
  end

  def from_stock
    @available.shift || (@count < @limit && allocate)
  end

  def method_missing(sym, *args, &block)
    acquire { |r| r.send(sym, *args, &block) }
  end

  def respond_to_missing?(*_args)
    true
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
