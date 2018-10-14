# frozen_string_literal: true

export :invoke, :size

require 'fiber'

# Array of available fibers
@pool = []

# Fiber count
@count = 0

# Returns number of available fibers in pool
# @return [Integer] available fibers count
def available
  @pool.size
end

# Returns size of fiber pool (including currently used fiber)
# @return [Integer] fiber pool size
def size
  @count
end

# Invokes the given block using a fiber taken from the fiber pool. If the pool
# is exhausted, a new fiber will be created.
# @return [void]
def invoke(&block)
  fib = @pool.empty? ? new_fiber : @pool.pop
  @job = block
  fib.resume
end

# Creates a new fiber to be added to the pool
# @return [Fiber] new fiber
def new_fiber
  @count += 1
  Fiber.new { fiber_loop }
end

# Runs a job-processing loop inside the current fiber
# @return [void]
def fiber_loop
  fiber = Fiber.current
  loop do
    job = @job
    @job = nil
    result = job&.(fiber)

    @pool << fiber
    Fiber.yield result
  end
end
