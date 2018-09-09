# A way to run async ops synchronously

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

$reactor_loop_fiber = Fiber.new do
  Core::Reactor.run
end

def await(promise = {}, *more)
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
await sleep(1)
puts "Elapsed: #{Time.now - t0}"

