# frozen_string_literal: true

export  :available,
        :checked_out,
        :reset!,
        :size,
        :run

require 'fiber'

# Array of available fibers
@pool = []

# Array of fibers in use
@checked_out = {}

# Fiber count
@count = 0

# Returns number of available fibers in pool
# @return [Integer] available fibers count
def available
  @pool.size
end

def checked_out
  @checked_out.size
end

# Returns size of fiber pool (including currently used fiber)
# @return [Integer] fiber pool size
def size
  @count
end

def downsize
  return if @count < 5
  max_available = @count >= 5 ? @count / 5 : 2
  if @pool.count > max_available
    @pool.slice!(max_available, 50).each { |f| f.transfer :stop }
  end
end

@downsize_timer = EV::Timer.new(5, 5)
@downsize_timer.start { downsize }
EV.unref

# Invokes the given block using a fiber taken from the fiber pool. If the pool
# is exhausted, a new fiber will be created.
# @return [Fiber]
def run(&block)
  fiber = @pool.empty? ? new_fiber : @pool.shift
  fiber.next_job = block
  fiber
end

def reset!
  @count = 0
  @pool = []
  @checked_out = {}
end

# Creates a new fiber to be added to the pool
# @return [Fiber] new fiber
def new_fiber
  Fiber.new { fiber_loop }
end

# Runs a job-processing loop inside the current fiber
# @return [void]
def fiber_loop
  fiber = Fiber.current
  @count += 1
  error = nil
  loop do
    job, fiber.next_job = fiber.next_job, nil
    @checked_out[fiber] = true
    fiber.cancelled = nil
    
    job&.(fiber)

    @pool << fiber
    @checked_out.delete(fiber)
    break if suspend == :stop
  end
rescue => e
  # uncaught error
  error = e
ensure
  @pool.delete(self)
  @checked_out.delete(fiber)
  @count -= 1

  # We need to explicitly transfer control to reactor fiber, otherwise it will
  # be transferred to the main fiber, which would normally be blocking on 
  # something
  $__reactor_fiber__.transfer unless error
end
