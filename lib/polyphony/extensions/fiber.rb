# frozen_string_literal: true

require 'fiber'

Exceptions = import '../core/exceptions'

# Fiber control API
module FiberControl
  def await
    if @running == false
      return @result.is_a?(Exception) ? (raise @result) : @result
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
  include FiberControl
  include FiberMessaging

  # map of currently running fibers
  def self.root
    @root_fiber
  end

  def self.reset!
    @root_fiber = current
    @running_fibers_map = { @root_fiber => true }
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

  def self.spin(orig_caller = caller, &block)
    f = new { |v| f.run(v) }
    f.setup(block, orig_caller)
    f
  end

  def setup(block, caller)
    @calling_fiber = Fiber.current
    @caller = caller
    @block = block
    schedule
  end

  def run(first_value)
    raise first_value if first_value.is_a?(Exception)

    @running = true
    self.class.map[self] = true
    result = @block.(first_value)
    finish_execution(result)
  rescue Exceptions::MoveOn => e
    finish_execution(e.value)
  rescue Exception => e
    finish_execution(e, true)
  end

  def finish_execution(result, uncaught_exception = false)
    @result = result
    @running = false
    self.class.map.delete(self)
    @when_done&.(result)
    @waiting_fiber&.schedule(result)

    return unless uncaught_exception && !@waiting_fiber

    parent_fiber = @calling_fiber.running? ? @calling_fiber : Fiber.root
    parent_fiber.schedule(result)
  ensure
    Gyro.run
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
    @caller ||= []
    if @calling_fiber
      @caller + @calling_fiber.caller
    else
      @caller
    end
  end
end
