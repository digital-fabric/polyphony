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

    def acquire
      fiber = Fiber.current
      return @acquired_resources[fiber] if @acquired_resources[fiber]

      add_to_stock if (@stock.empty? || @stock.pending?) && @size < @limit 
      resource = @stock.shift
      @acquired_resources[fiber] = resource
      yield resource
    ensure
      if resource && @acquired_resources.delete(fiber) == resource
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
      @stock << @allocator.call
    end

    # Discards the currently-acquired resource
    # instead of returning it to the pool when done.
    def discard!(fiber = Fiber.current)
      if @acquired_resources.delete(fiber)
        @size -= 1
      end
    end

    def preheat!
      add_to_stock while @size < @limit
    end
  end
end
