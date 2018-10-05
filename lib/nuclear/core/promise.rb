# frozen_string_literal: true

export_default :Promise

require 'fiber'
require_relative '../../ev_ext'

# Encapsulates the eventual completion or failure of an asynchronous operation
# (loosely based on the Javascript Promise API
class Promise
  # Fiber associated
  attr_accessor :fiber
  attr_writer :fulfilled_handler, :rejected_handler

  # Initializes a new Promise, passing self to the given block. The following
  # options are accepted:
  #
  #   :recurring      set to true for a recurring/generator promise
  #   :then           callback for successful completion
  #   :catch          callback for error
  #   :timeout        timeout in seconds
  #
  # @param opts [Hash] options
  def initialize(opts = {})
    @pending = true
    @recurring = opts[:recurring]

    @fulfilled_handler = opts[:then]
    @rejected_handler  = opts[:catch]
    timeout(opts[:timeout]) if opts[:timeout]
    yield(self) if block_given?
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
    !@recurring && (@fulfilled || @rejected)
  end

  # Returns resolved value/error if promise is completed
  # @return [any]
  def result
    (@fulfilled || @rejected) && @value
  end

  # Returns resolved value/error, clearing it
  # @return [any]
  def clear_result
    @fulfilled = false
    @rejected = false
    @value
  end

  # Resolves the promise with the given value
  # @return [void]
  def resolve(value = nil)
    @fulfilled = true
    complete(value)
  end

  # Alias for the #resolve method, so the promise could be resolved as a
  # callable, e.g. `promise.(value)`
  alias_method :call, :resolve

  # Completes the promise with the given error
  # @param err [Exception] raised error
  # @return [void]
  def reject(err)
    @rejected = true
    complete(err)
  end

  # Completes the promise, resuming the associated fiber or firing the
  # associated callbacks, finally passing control to any chained promise
  # @param value [any] resolved value / error
  # @return [void]
  def complete(value)
    @pending = false unless @recurring
    @timeout&.stop
    @value = value
    if @fiber
      @fiber.resume(value)
    else
      proc = value.is_a?(Exception) ? @rejected_handler : @fulfilled_handler
      proc&.(value)
    end
  end

  # Sets the callback for successful completion
  # @return [void]
  def then(proc = nil, &block)
    Promise.new do |p|
      block ||= proc
      @fulfilled_handler = proc { |v| resolve_then(p, block, v) }
      @rejected_handler  = proc { |e| p.reject(e) }

      @fulfilled_handler.(@value) if @fulfilled
    end
  end

  # Sets the callback for failed (error) completion
  # @return [void]
  def catch(proc = nil, &block)
    Promise.new do |p|
      block ||= proc
      @fulfilled_handler = proc { |v| p.resolve(v) }
      @rejected_handler  = block
    end
  end

  def resolve_then(promise, block, value)
    r = block.(value)
    if r.is_a?(Promise)
      r.fulfilled_handler = proc { |v| promise.resolve(v) }
      r.rejected_handler  = proc { |e| promise.reject(e) }
    else
      promise.resolve(value)
    end
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
    @timeout = EV::Timer.new(interval, 0) do
      block&.()
      reject(TimeoutError.new(TIMEOUT_MESSAGE))
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
