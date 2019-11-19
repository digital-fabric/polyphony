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
    fiber = Fiber.new { fiber_loop }
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
def fiber_loop
  fiber = Fiber.current
  loop do
    job, fiber.__next_pool_job__ = fiber.__next_pool_job__, nil
    fiber.cancelled = nil
    
    job&.(fiber)

    check_fiber_in(fiber)
    break if suspend == :stop
  end
rescue => e
  # uncaught error
  $stdout.orig_puts "uncaught error in FiberPool: #{e.inspect}"
  $stdout.orig_puts e.backtrace.join("\n")
ensure
  @total_count -= 1
  # We need to explicitly transfer control to reactor fiber, otherwise it will
  # be transferred to the main fiber, which would normally be blocking on 
  # something
  $__reactor_fiber__.transfer
end

def run_job(&job)
  error = nil
  job&.(Fiber.current)
rescue => e
  # uncaught error
  $stdout.orig_puts "uncaught error in FiberPool: #{e.inspect}"
  $stdout.orig_puts e.backtrace.join("\n")
  error = e
ensure
  # Kernel.orig_puts
  # We need to explicitly transfer control to reactor fiber, otherwise it will
  # be transferred to the main fiber, which would normally be blocking on 
  # something
  $__reactor_fiber__.transfer unless error

end