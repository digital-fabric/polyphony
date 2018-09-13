# frozen_string_literal: true

export_default :Async

require 'fiber'

FiberPool = import('./fiber_pool')
Promise   = import('./promise')

import('../ext/fiber')

extend import('./reactor')

# Async methods
module Async
  INVALID_PROMISE_MSG = 'await accepts promises only'
  ASYNC_ONLY_MSG = 'await can only be called inside async block'

  # Yields control to other fibers while waiting for given promise(s) to resolve
  # if the resolved value is an error, it is raised
  # @param promise [Promise] promise
  # @param more [Array<Promise>] more promises
  # @return [any] resolved value
  def await(promise = {}, *more)
    return await_all(promise, *more) unless more.empty?

    raise FiberError, INVALID_PROMISE_MSG unless promise.is_a?(Promise)
    raise FiberError, ASYNC_ONLY_MSG unless Fiber.current.async?
    if promise.completed?
      # promise has already resolved
      return_value = promise.clear_result
    else
      promise.fiber = Fiber.current
      # it's here that execution stops, it will resume once the promise is
      # resolved (see Promise#complete)
      return_value = Fiber.yield
    end
    return_value.is_a?(Exception) ? raise(return_value) : return_value
  end

  # Await for all given promises to resolve
  # @return [Promise] promise
  def await_all(*promises)
    await(parallel(promises, -1))
  end

  # Await for 1 or more of the given promises to resolve
  # @return [Promise] promise
  def await_any(*promises)
    await(parallel(promises, 1))
  end

  # Creates a generator/recurring promise
  # @return [Promise] promise
  def generator(&block)
    Promise.new(recurring: true, &block)
  end

  # Creates a new promise
  # @return [Promise] promise
  def promise(*args, &block)
    Promise.new(*args, &block)
  end

  # Creates a recurring promise that will fire (resolve) every <interval>
  # seconds
  # @param interval [Float] interval in seconds
  # @return [Promise] promise
  def pulse(interval)
    Promise.new(recurring: true) do |p|
      timer_id = MODULE.interval(interval, &p)
      p.on_stop { MODULE.cancel_timer(timer_id) }
    end
  end

  # Runs an asynchronous operation. The given block is expected to use await to
  # yield to other fibers while waiting for blocking operations (such as I/O or
  # timers)
  def async(*args, &block)
    FiberPool.() do |fiber|
      fiber.async! # important: the async flag is checked by await
      block = args.shift if args.first.is_a?(Proc) && !block
      block.(*args)
    end
  end

  # Creates a promise that will resolve after the given duration
  # @param duration [Float] duration in seconds
  # @return [Promise] promise
  def sleep(duration)
    Promise.new { |p| MODULE.timeout(duration, &p) }
  end

  # Creates a promise waiting for 1 or more of the given promises in parallel
  # @param promises [Array<Promise>] array of promises
  # @param count [Integer] minimum number of resolutions to wait for or -1 (all)
  # @return [Promise] promise
  def parallel(promises, count = -1)
    count = promises.count if count == -1
    Promise.new { |all| reduce_promises(all, promises, count) }
  end

  # Setups parallel execution of given promises, passing the resolved values to
  # the wrapper promise
  # @param parallel_promise [Promise] wrapper promise
  # @param promises [Array<Promise>] array of promises
  # @param count [Integer] minimum number of resolutions to wait for or -1 (all)
  # @return [void]
  def reduce_promises(parallel_promise, promises, count)
    completed = 0
    values = []
    promises.each_with_index do |p, idx|
      p.then do |v|
        values[idx] = v
        completed += 1
        parallel_promise.resolve(values) if completed == count
      end.catch { |e| parallel_promise.reject(e) }
    end
  end
end

extend Async

# Promise extensions
class Promise
  # Iterates asynchronously over each resolution of a recurring promise. This
  # method can only be called inside of an async block.
  # @return [void]
  def each
    until @stopped
      result = MODULE.await self
      result ? yield(result) : break
    end
  end
end
