# frozen_string_literal: true

require 'fiber'

Exceptions = import '../core/exceptions'

# Fiber control API
module FiberControl
  def await
    if @running == false
      return @result.is_a?(Exception) ? (Kernel.raise @result) : @result
    end

    @waiting_fiber = Fiber.current
    suspend
  ensure
    @waiting_fiber = nil
  end
  alias_method :join, :await

  def interrupt(value = nil)
    return if @running == false

    schedule Exceptions::MoveOn.new(nil, value)
    snooze
  end
  alias_method :stop, :interrupt

  def cancel!
    return if @running == false

    schedule Exceptions::Cancel.new
    snooze
  end

  def raise(*args)
    error = error_from_raise_args(args)
    schedule(error)
    snooze
  end

  def error_from_raise_args(args)
    case (arg = args.shift)
    when String then RuntimeError.new(arg)
    when Class  then arg.new(args.shift)
    when Exception then arg
    else RuntimeError.new
    end
  end
end

# Messaging functionality
module FiberMessaging
  def <<(value)
    if @receive_waiting && @running
      schedule value
    else
      @queued_messages ||= []
      @queued_messages << value
    end
    snooze
  end

  def receive
    if !@queued_messages || @queued_messages&.empty?
      wait_for_message
    else
      value = @queued_messages.shift
      snooze
      value
    end
  end

  def wait_for_message
    Gyro.ref
    @receive_waiting = true
    suspend
  ensure
    Gyro.unref
    @receive_waiting = nil
  end
end

# Fiber extensions
class ::Fiber
  prepend FiberControl
  include FiberMessaging

  def self.reset!
    @running_fibers_map = { Thread.current.main_fiber => true }
  end

  reset!

  def self.map
    @running_fibers_map
  end

  def self.list
    @running_fibers_map.keys
  end

  def self.count
    @running_fibers_map.size
  end

  def self.spin(tag = nil, orig_caller = caller, &block)
    f = new { |v| f.run(v) }
    f.setup(tag, block, orig_caller)
    f
  end

  attr_accessor :tag
  Fiber.current.tag = :main

  def setup(tag, block, caller)
    __fiber_trace__(:fiber_create, self)
    @tag = tag
    @calling_fiber = Fiber.current
    @caller = caller
    @block = block
    schedule
  end

  def run(first_value)
    Kernel.raise first_value if first_value.is_a?(Exception)

    start_execution(first_value)
  rescue ::Interrupt, ::SystemExit => e
    Thread.current.main_fiber.transfer e.class.new
  rescue Exceptions::MoveOn => e
    finish_execution(e.value)
  rescue Exception => e
    finish_execution(e, true)
  end

  def start_execution(first_value)
    @running = true
    self.class.map[self] = true
    result = @block.(first_value)
    finish_execution(result)
  end

  def finish_execution(result, uncaught_exception = false)
    __fiber_trace__(:fiber_terminate, self, result)
    @result = result
    @running = false
    self.class.map.delete(self)
    @when_done&.(result)
    @waiting_fiber&.schedule(result)
    return unless uncaught_exception && !@waiting_fiber

    exception_receiving_fiber.schedule(result)
  ensure
    Thread.current.switch_fiber
  end

  def exception_receiving_fiber
    @calling_fiber.running? ? @calling_fiber : Thread.current.main_fiber
  end

  attr_reader :result

  def running?
    @running
  end

  def when_done(&block)
    @when_done = block
  end

  def inspect
    "#<Fiber:#{object_id} #{location} (#{state})>"
  end
  alias_method :to_s, :inspect

  def location
    @caller ? @caller[0] : '(root)'
  end

  def caller
    spin_caller = @caller || []
    if @calling_fiber
      spin_caller + @calling_fiber.caller
    else
      spin_caller
    end
  end
end
