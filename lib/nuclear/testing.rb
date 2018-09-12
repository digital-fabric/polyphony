# frozen_string_literal: true

Core = import('./core')

ReactorLoopFiber = Fiber.new do
  Nuclear.run_reactor
end

module Core
  def self.await(promise = {}, *more)
    return await_all(promise, *more) unless more.empty?

    # raise FiberError, AWAIT_ERROR_MSG unless Fiber.current.async?
    if promise.completed?
      return_value = promise.clear_result
    else
      until promise.completed?
        ReactorLoopFiber.resume      
      end      
      return_value = return_value = promise.result
    end
    return_value.is_a?(Exception) ? raise(return_value) : return_value
  end

  def self.async(&block)
    block.()
  end
end
