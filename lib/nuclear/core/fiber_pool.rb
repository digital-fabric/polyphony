# frozen_string_literal: true

export :spawn, :size, :available

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

@last_downsize_stamp = Time.now

# Invokes the given block using a fiber taken from the fiber pool. If the pool
# is exhausted, a new fiber will be created.
# @return [Fiber]
def spawn(&block)
  now = Time.now
  downsize(now) if now - @last_downsize_stamp >= 60

  fiber = @pool.empty? ? new_fiber : @pool.pop
  @next_job = block
  fiber.resume
end

def downsize(now)
  @last_downsize_stamp = now
  return if @count < 10
  max_available = @count >= 50 ? @count / 5 : 10
  if @pool.count > max_available
    @pool.slice!(max_available, 10).each { |f| f.resume :stop }
  end
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
  loop do
    job = @next_job
    @next_job = nil
    job&.(fiber)
    job = nil
    @pool << fiber
    break if Fiber.yield == :stop
  end
ensure
  @count -= 1
end
