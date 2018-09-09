# A way to run async ops synchronously

require 'modulation'

Nuclear = import('../../lib/nuclear')

$reactor_loop_fiber = Fiber.new do
  Nuclear.async_reactor
end

def Nuclear.await(promise = {}, *more)
  return await_all(promise, *more) unless more.empty?

  # raise FiberError, AWAIT_ERROR_MSG unless Fiber.current.async?
  if promise.completed?
    # promise has already resolved
    return_value = promise.clear_result
  else
    until promise.completed?
      $reactor_loop_fiber.resume      
    end      
    return_value = return_value = promise.result
  end
  return_value.is_a?(Exception) ? raise(return_value) : return_value
end

t0 = Time.now
Nuclear.await Nuclear.sleep(1)
puts "Elapsed: #{Time.now - t0}"

