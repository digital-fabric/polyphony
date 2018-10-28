# frozen_string_literal: true

export :spawn, :size, :available, :checked_out

require 'fiber'

# Array of available fibers
@pool = []

# Array of fibers in use
@checked_out = []

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

# Invokes the given block using a fiber taken from the fiber pool. If the pool
# is exhausted, a new fiber will be created.
# @return [Fiber]
def spawn(&block)
  fiber = @pool.empty? ? new_fiber : @pool.shift
  @next_job = block
  fiber.resume
end

def downsize
  return if @count < 5
  max_available = @count >= 5 ? @count / 5 : 2
  if @pool.count > max_available
    @pool.slice!(max_available, 50).each { |f| f.resume :stop }
  end
end

@downsize_timer = EV::Timer.new(10, 10)
@downsize_timer.start { downsize }
EV.unref

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
  loop do
    @checked_out << fiber
    job = @next_job
    @next_job = nil
    job&.(fiber)
    job = nil
    @pool << fiber
    @checked_out.delete(fiber)
    break if Fiber.yield == :stop
  end
ensure
  @count -= 1
end
