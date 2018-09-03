# frozen_string_literal: true

export :async,
       :await,
       :await_any,
       :await_all,
       :generator,
       :pulse,
       :promise,
       :sleep

require 'fiber'

# Fiber extensions
class ::Fiber
  # Returns true if fiber is marked as async
  # @return [Boolean] is fiber async
  def async?
    @async
  end

  # Marks the fiber as async
  # @return [void]
  def async!
    @async = true
  end
end

FiberPool = import('./fiber_pool')
Reactor = import('./reactor')

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

AWAIT_ERROR_MSG = 'await can only be called inside async block'

# Yields control to other fibers while waiting for given promise(s) to resolve
# if the resolved value is an error, it is raised
# @param promises [Array<Promise>] one or more promises
# @return [any] resolved value
def await(*promises)
  return await_all(*promises) if promises.size > 1
  raise FiberError, AWAIT_ERROR_MSG unless Fiber.current.async?
  promise = promises.first

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

# Await for 1 or more of the given promises to resolve
# @return [Promise] promise
def await_any(*promises)
  await(Promise.some(promises, 1))
end

# Await for all given promises to resolve
# @return [Promise] promise
def await_all(*promises)
  await(Promise.some(promises, -1))
end

# Creates a new promise
# @return [Promise] promise
def promise(*args, &block)
  Promise.new(*args, &block)
end

# Creates a generator/recurring promise
# @return [Promise] promise
def generator(&block)
  Promise.new(recurring: true, &block)
end

# Creates a promise that will resolve after the given duration
# @param duration [Float] duration in seconds
# @return [Promise] promise
def sleep(duration)
  Promise.new { |p| Reactor.timeout(duration, &p) }
end

# Creates a recurring promise that will fire (resolve) every <interval> seconds
# @param interval [Float] interval in seconds
# @return [Promise] promise
def pulse(interval)
  Promise.new(recurring: true) do |p|
    puts "pulse #{p.inspect}"
    timer_id = Reactor.interval(interval, &p)
    p.on_stop { Reactor.cancel_timer(timer_id) }
  end
end

# Encapsulates the eventual completion or failure of an asynchronous operation
# (loosely based on the Javascript Promise API
class Promise
  # Creates a promise waiting for 1 or more of the given promises in parallel
  # @param promises [Array<Promise>] array of promises
  # @param count [Integer] minimum number of resolutions to wait for or -1 (all)
  # @return [Promise] promise
  def self.some(promises, count = -1)
    count = promises.count if count == -1
    new { |all| reduce_promises(all, promises, count) }
  end

  # Setups parallel execution of given promises, passing the resolved values to
  # the wrapper promise
  # @param wrapper_promise [Promise] wrapper promise
  # @param promises [Array<Promise>] array of promises
  # @param count [Integer] minimum number of resolutions to wait for or -1 (all)
  # @return [void]
  def self.reduce_promises(wrapper_promise, promises, count)
    completed = 0
    values = []
    promises.each_with_index do |p, idx|
      p.then do |v|
        values[idx] = v
        completed += 1
        wrapper_promise.resolve(values) if completed == count
      end
      p.catch { |e| wrapper_promise.error(e) }
    end
  end

  # Fiber associated
  attr_accessor :fiber

  # Initializes a new Promise, passing self to the given block. The following
  # options are accepted:
  #
  #   :recurring      set to true for a recurring/generator promise
  #   :then           callback for successful completion
  #   :catch          callback for error
  #   :timeout        timeout in seconds
  #   :link           promise to link to for sequential execution
  #
  # The given block will be executed immediately, unless the promise is chained
  # to another promise using :link, in which case the block will be executed
  # once the other promise is completed
  # @param opts [Hash] options
  def initialize(opts = {}, &block)
    @pending = true
    @recurring = opts[:recurring]

    @then = opts[:then]
    @catch = opts[:catch]
    timeout(opts[:timeout]) if opts[:timeout]
    if opts[:link]
      opts[:link].chain(self)
      @action = block
    elsif block_given?
      yield self
    end
  end

  # Chain another promise to be executed once the promise is resolved
  # @param promise [Promise] subsequent promise
  # @return [void]
  def chain(promise)
    @next ? @next.chain(promise) : (@next = promise)
  end

  # Runs the action block for a promise that was chained (that is the block
  # that was passed to Promise.new)
  # @return [void]
  def run
    @action&.(self)
  end

  # Returns true if the promise is not completed (or is recurring)
  # @return [Boolean]
  def pending?
    @pending
  end

  # Returns true if the promise is recurring
  # @return [Boolean]
  def recurring?
    @recurring
  end

  # Returns true if the promise is completed
  # @return [Boolean]
  def completed?
    !@recurring && (@resolved || @errored)
  end

  # Returns resolved value/error if promise is completed
  # @return [any]
  def result
    (@resolved || @errored) && @value
  end

  # Returns resolved value/error, clearing it
  # @return [any]
  def clear_result
    @resolved = false
    @errored = false
    @value
  end

  # Resolves the promise with the given value
  # @return [void]
  def resolve(value = nil)
    @resolved = true
    complete(value)
  end

  # Alias for the #resolve method, so the promise could be resolved as a
  # callable, e.g. `promise.(value)`
  alias_method :call, :resolve

  # Completes the promise with the given error
  # @param err [Exception] raised error
  # @return [void]
  def error(err)
    @errored = true
    complete(err)
  end

  # Completes the promise, resuming the associated fiber or firing the
  # associated callbacks, finally passing control to any chained promise
  # @param value [any] resolved value / error
  # @return [void]
  def complete(value)
    @pending = false unless @recurring
    Reactor.cancel_timer(@timeout) if @timeout
    @value = value
    if @fiber
      @fiber.resume(value)
    else
      (value.is_a?(Exception) ? @catch : @then)&.(value)
    end

    # run next promised action (if chained)
    @next&.run
  end

  # Sets the callback for successful completion
  # @return [void]
  def then(proc = nil, &block)
    @then = proc || block
    @then.(@value) if @resolved
    self
  end

  # Sets the callback for failed (error) completion
  # @return [void]
  def catch(proc = nil, &block)
    @catch = proc || block
    @catch.(@value) if @errored
    self
  end

  # Converts the promise into a Proc. This allows a promise to be coerced into
  # a block, e.g. `io.gets(&promise)`
  # @return [Proc]
  def to_proc
    proc { |value| resolve(value) }
  end

  # Timeout error raised when a promise times out
  class TimeoutError < RuntimeError
  end

  TIMEOUT_MESSAGE = 'Timeout occurred'

  # Sets a timeout for the promise. The given block will be executed upon
  # timeout, allowing for the cancellation of any pending operations
  # @return [void]
  def timeout(interval, &block)
    @timeout = Reactor.timeout(interval) do
      block&.()
      error(TimeoutError.new(TIMEOUT_MESSAGE))
    end
  end

  # Iterates asynchronously over each resolution of a recurring promise. This
  # method can only be called inside of an async block.
  # @return [void]
  def each
    until @stopped
      result = MODULE.await self
      yield(result) if result
    end
  end

  # Stops a recurring promise, running the callback given to #on_stop
  # @return [void]
  def stop
    @stopped = true
    @on_stop&.()
    resolve(nil)
  end

  # Sets a callback to be called when a recurring promise is stopped
  # @return [void]
  def on_stop(&block)
    @on_stop = block
  end
end
