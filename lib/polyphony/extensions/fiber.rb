# frozen_string_literal: true

require 'fiber'

Exceptions = import '../core/exceptions'

# Fiber control API
module FiberControl
  def await
    if @running == false
      return @result.is_a?(Exception) ? (Kernel.raise @result) : @result
    end

    fiber = Fiber.current
    @waiting_fibers ||= {}
    @waiting_fibers[fiber] = true
    suspend
  ensure
    @waiting_fibers&.delete(fiber)
  end
  alias_method :join, :await

  def interrupt(value = nil)
    return if @running == false

    schedule Exceptions::MoveOn.new(nil, value)
  end
  alias_method :stop, :interrupt

  def cancel!
    return if @running == false

    schedule Exceptions::Cancel.new
  end

  def terminate
    return if @running == false

    schedule Exceptions::Terminate.new
  end

  def raise(*args)
    error = error_from_raise_args(args)
    schedule(error)
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

# Class methods for controlling fibers (namely await and select)
module FiberControlClassMethods
  def await(*fibers)
    return [] if fibers.empty?

    state = setup_await_select_state(fibers)
    await_setup_monitoring(fibers, state)
    suspend
    fibers.map(&:result)
  ensure
    await_select_cleanup(state)
  end
  alias_method :join, :await

  def setup_await_select_state(fibers)
    {
      awaiter: Fiber.current,
      pending: fibers.each_with_object({}) { |f, h| h[f] = true }
    }
  end

  def await_setup_monitoring(fibers, state)
    fibers.each do |f|
      f.when_done { |r| await_fiber_done(f, r, state) }
    end
  end

  def await_fiber_done(fiber, result, state)
    state[:pending].delete(fiber)

    if state[:cleanup]
      state[:awaiter].schedule if state[:pending].empty?
    elsif !state[:done] && (result.is_a?(Exception) || state[:pending].empty?)
      state[:awaiter].schedule(result)
      state[:done] = true
    end
  end

  def await_select_cleanup(state)
    return if state[:pending].empty?

    move_on = Exceptions::MoveOn.new
    state[:cleanup] = true
    state[:pending].each_key { |f| f.schedule(move_on) }
    suspend
  end

  def select(*fibers)
    state = setup_await_select_state(fibers)
    select_setup_monitoring(fibers, state)
    suspend
  ensure
    await_select_cleanup(state)
  end

  def select_setup_monitoring(fibers, state)
    fibers.each do |f|
      f.when_done { |r| select_fiber_done(f, r, state) }
    end
  end

  def select_fiber_done(fiber, result, state)
    state[:pending].delete(fiber)
    if state[:cleanup]
      # in cleanup mode the selector is resumed if no more pending fibers
      state[:awaiter].schedule if state[:pending].empty?
    elsif !state[:selected]
      # first fiber to complete, we schedule the result
      state[:awaiter].schedule([fiber, result])
      state[:selected] = true
    end
  end
end

# Messaging functionality
module FiberMessaging
  def <<(value)
    @mailbox << value
    snooze
  end
  alias_method :send, :<<

  def receive
    @mailbox.shift
  end

  def receive_pending
    @mailbox.shift_each
  end
end

# Methods for controlling child fibers
module ChildFiberControl
  def children
    (@children ||= {}).keys
  end

  def spin(tag = nil, orig_caller = caller, &block)
    f = Fiber.new { |v| f.run(v) }
    f.prepare(tag, block, orig_caller)
    (@children ||= {})[f] = true
    f
  end

  def child_done(child_fiber)
    @children.delete(child_fiber)
  end

  def terminate_all_children
    return unless @children

    e = Exceptions::Terminate.new
    @children.each_key { |c| c.raise e }
  end

  def await_all_children
    return unless @children && !@children.empty?

    Fiber.await(*@children.keys)
  end
end

# Fiber extensions
class ::Fiber
  prepend FiberControl
  include FiberMessaging
  include ChildFiberControl

  extend FiberControlClassMethods

  attr_accessor :tag, :thread

  def prepare(tag, block, caller)
    __fiber_trace__(:fiber_create, self)
    @thread = Thread.current
    @tag = tag
    @parent = Fiber.current
    @caller = caller
    @block = block
    @mailbox = Gyro::Queue.new
    schedule
  end

  def setup_main_fiber
    @main = true
    @tag = :main
    @thread = Thread.current
    @running = true
    @children&.clear
    @mailbox = Gyro::Queue.new
  end

  def run(first_value)
    setup(first_value)
    uncaught = nil
    result = @block.(first_value)
  rescue Exceptions::MoveOn, Exceptions::Terminate => e
    result = e.value
  rescue Exception => e
    result = e
    uncaught = true
  ensure
    finalize(result, uncaught)
  end

  def setup(first_value)
    Kernel.raise first_value if first_value.is_a?(Exception)

    @running = true
  end

  def finalize(result, uncaught_exception = false)
    terminate_all_children
    await_all_children
    __fiber_trace__(:fiber_terminate, self, result)
    @result = result
    @running = false
    inform_dependants(result, uncaught_exception)
  ensure
    Thread.current.switch_fiber
  end

  def inform_dependants(result, uncaught_exception)
    @parent.child_done(self)
    @when_done_procs&.each { |p| p.(result) }
    has_waiting_fibers = nil
    @waiting_fibers&.each_key do |f|
      has_waiting_fibers = true
      f.schedule(result)
    end
    return unless uncaught_exception && !has_waiting_fibers

    # propagate unaught exception to parent
    @parent.schedule(result)
  end

  attr_reader :result

  def running?
    @running
  end

  def when_done(&block)
    (@when_done_procs ||= []) << block
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
    if @parent
      spin_caller + @parent.caller
    else
      spin_caller
    end
  end

  def main?
    @main
  end
end

Fiber.current.setup_main_fiber

at_exit do
  Fiber.current.terminate_all_children
  Fiber.current.await_all_children
end
