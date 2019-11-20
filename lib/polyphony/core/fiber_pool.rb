# frozen_string_literal: true

export  :allocate,
        :available_count,
        :checked_out_count,
        :reset!,
        :total_count

require 'fiber'

class ::Fiber
  attr_accessor :__next_pool_job__, :__next_pool_fiber__
end

# Array of available fibers
@pool = []
@pool_head = nil
@pool_tail = nil

# Fiber count
@total_count = 0
@checked_out_count = 0

# Returns number of available fibers in pool
# @return [Integer] available fibers count
def available_count
  @total_count - @checked_out_count
end

def checked_out_count
  @checked_out_count
end

# @return [Integer] fiber pool size
def total_count
  @total_count
end

# def downsize
#   return if @count < 5
#   max_available = @count >= 5 ? @count / 5 : 2
#   if @pool.count > max_available
#     @pool.slice!(max_available, 50).each { |f| f.transfer :stop }
#   end
# end

# @downsize_timer = Gyro::Timer.new(5, 5)
# @downsize_timer.start { downsize }
# Gyro.unref

# Invokes the given block using a fiber taken from the fiber pool. If the pool
# is exhausted, a new fiber will be created.
# @return [Fiber]
def allocate(&block)
  check_fiber_out.tap { |f| f.__next_pool_job__ = block }
end

def check_fiber_out
  @checked_out_count += 1
  if @pool_head
    fiber = @pool_head
    @pool_head = @pool_head.__next_pool_fiber__
    return fiber
  else
    @fiber_loop_proc ||= method(:fiber_loop).to_proc
    fiber = Fiber.new(&@fiber_loop_proc)
    @total_count += 1
    return fiber
  end
end

def check_fiber_in(fiber)
  @checked_out_count -= 1
  if @pool_head
    @pool_tail.__next_pool_fiber__ = fiber
    @pool_tail = fiber
  else
    @pool_head = @pool_tail = fiber
  end
  @pool_tail.__next_pool_fiber__ = nil
end

def reset!
  @total_count = 0
  @checked_out_count = 0
  @pool_head = nil
end

# Runs a job-processing loop inside the current fiber
# @return [void]
def fiber_loop(value)
  fiber = Fiber.current
  loop do
    job, fiber.__next_pool_job__ = fiber.__next_pool_job__, nil
    run_job(job, value, fiber) if job
    check_fiber_in(fiber)

    value = suspend
    break if value == :stop
  end
ensure
  @total_count -= 1
  # We need to explicitly transfer control to reactor fiber, otherwise it will
  # be transferred to the main fiber, which might be blocking on some operation
  # or just waiting for the reactor loop to finish running.
  $__reactor_fiber__.transfer
end

def run_job(job, value, fiber)
  fiber.cancelled = nil
  job.(value)
rescue Exception => e
  if fiber.respond_to?(:__calling_fiber__)
    fiber.__calling_fiber__.transfer e
  else
    Fiber.main.transfer e
  end
end
