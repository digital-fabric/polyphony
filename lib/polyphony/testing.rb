# frozen_string_literal: true

Core = import('./core')

# Fiber used for running reactor loop
ReactorLoopFiber = Fiber.new do
  Polyphony.run_reactor
end

# Monkey-patch core module with async/await methods
module Core
  # Processes a promise by running reactor loop until promise is completed
  # @param promise [Promise] promise
  # @param more [Array<Promise>] more promises
  # @return [any] resolved value
  def self.await(promise = {}, *more)
    return await_all(promise, *more) unless more.empty?

    # raise FiberError, AWAIT_ERROR_MSG unless Fiber.current.async?
    if promise.completed?
      return_value = promise.clear_result
    else
      ReactorLoopFiber.transfer until promise.completed?
      return_value = promise.result
    end
    return_value.is_a?(Exception) ? raise(return_value) : return_value
  end

  # Runs given block
  # @return [void]
  def self.async(&block)
    block.()
  end
end
