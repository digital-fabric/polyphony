# frozen_string_literal: true

module Polyphony
  # Implements a limited resource pool
  class ResourcePool
    attr_reader :limit, :size

    # Initializes a new resource pool
    # @param opts [Hash] options
    # @param &block [Proc] allocator block
    def initialize(opts, &block)
      @allocator = block
      @limit = opts[:limit] || 4
      @size = 0
      @stock = Polyphony::Queue.new
      @acquired_resources = {}
    end

    def available
      @stock.size
    end

    def acquire(&block)
      fiber = Fiber.current
      return yield @acquired_resources[fiber] if @acquired_resources[fiber]

      acquire_from_stock(fiber, &block)
    end

    def acquire_from_stock(fiber)
      add_to_stock if (@stock.empty? || @stock.pending?) && @size < @limit 
      resource = @stock.shift
      @acquired_resources[fiber] = resource
      yield resource
    ensure
      if resource && @acquired_resources[fiber] == resource
        @acquired_resources.delete(fiber)
        @stock.push resource
      end
    end
        
    def method_missing(sym, *args, &block)
      acquire { |r| r.send(sym, *args, &block) }
    end

    def respond_to_missing?(*_args)
      true
    end

    # Allocates a resource
    # @return [any] allocated resource
    def add_to_stock
      @size += 1
      resource = @allocator.call
      @stock << resource
    end

    # Discards the currently-acquired resource
    # instead of returning it to the pool when done.
    def discard!
      @size -= 1 if @acquired_resources.delete(Fiber.current)
    end

    def preheat!
      add_to_stock while @size < @limit
    end
  end
end
