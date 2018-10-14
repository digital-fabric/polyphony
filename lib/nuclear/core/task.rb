# frozen_string_literal: true

export_default :Task

# Encapsulates an asynchronous task associated with a fiber. The task is
# initialized in a suspended state, unless the auto_start argument is true.
class Task
  attr_accessor :nexus
  attr_reader :fiber
  attr_writer :block

  # Initializes task with the given block
  # @param auto_start [boolean] whether the task should start (default: false)
  # @return [void]
  def initialize(opts = {}, &block)
    @block = block
    @opts = opts
    invoke if opts[:start]
  end

  # Completes the task by resuming the associated fiber with the given value
  # @param value [any] result of task
  # @return [void]
  def resolve(value)
    @yielded ? @fiber.resume(value) : (@resolved = value)
  end

  def on_cancel(&block)
    @on_cancel = block
  end

  def await(&block)
    @fiber = Fiber.current
    cancel_scope = @fiber.cancel_scope
    if cancel_scope&.cancelled?
      return nil
    end

    @block = block if block

    result = @block.(self)
    case result
    when Cancelled, MoveOn
      cancel!(result.cancel_scope)
      raise result
    when Exception
      raise result
    else
      result
    end
  end

  def invoke
    return if @block_called

    @fiber = Fiber.current
    @block_called = true
    @block.(self)
  end

  def yield
    return @resolved if @resolved
    @yielded = true
    Fiber.yield
  end

  def cancel!(_scope)
    @on_cancel&.()
  end
end
