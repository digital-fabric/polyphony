# frozen_string_literal: true

export_default :Promise

require 'fiber'

extend import('./reactor')

# Encapsulates the eventual completion or failure of an asynchronous operation
# (loosely based on the Javascript Promise API
class Promise
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
      chain_to(opts[:link], &block)
    elsif block_given?
      yield self
    end
  end

  # Chains the promise to another promise, with the given block executed once
  # the other promise has resolved
  def chain_to(promise, &block)
    promise.chain(self)
    @action = block
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
    MODULE.cancel_timer(@timeout) if @timeout
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
    Promise.new do |p|
      block ||= proc
      set_then  { |v| resolve_then(p, block, v) }
      set_catch { |e| p.error(e) }

      @then.(@value) if @resolved
    end

    # @then = proc || block
    
  end

  # Sets the callback for failed (error) completion
  # @return [void]
  def catch(proc = nil, &block)
    Promise.new do |p|
      block ||= proc
      set_then  { |v| p.resolve(v) }
      set_catch(&block)
    end
  end

  def set_then(&block)
    @then = block
  end

  def set_catch(&block)
    @catch = block
  end

  def resolve_then(promise, block, value)
    r = block.(value)
    if r.is_a?(Promise)
      r.set_then  { |v| promise.resolve(v) }
      r.set_catch { |e| promise.error(e) }
    else
      promise.resolve(value)
    end
  end
  
  # Sets the callback for both success and error completion
  def on_complete(proc = nil, &block)
    @then = @catch = proc || block
    @then.(@value) if @resolved
    @catch.(@value) if @errored
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
    @timeout = MODULE.timeout(interval) do
      block&.()
      error(TimeoutError.new(TIMEOUT_MESSAGE))
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
