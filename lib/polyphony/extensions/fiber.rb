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

module FiberControlClassMethods
  def await(*fibers)
    return if fibers.empty?

    pending = fibers.each_with_object({}) { |f, h| h[f] = true }
    current = Fiber.current
    done = nil
    fibers.each do |f|
      f.when_done do |r|
        pending.delete(f)
        if !done && (r.is_a?(Exception) || pending.empty?)
          current.schedule(r)
          done = true
        end
      end
    end
    suspend
    fibers.map(&:result)
  ensure
    move_on = Exceptions::MoveOn.new
    pending.each_key do |f|
      f.when_done do
        pending.delete(f)
        current.schedule if pending.empty?
      end
      f.schedule(move_on)
    end
    suspend until pending.empty?
  end
  alias_method :join, :await

  def select(*fibers)
    pending = fibers.each_with_object({}) { |f, h| h[f] = true }
    current = Fiber.current
    done = nil
    fibers.each do |f|
      f.when_done do |r|
        pending.delete(f)
        unless done
          current.schedule([f, r])
          done = true
        end
      end
    end
    suspend
  ensure
    move_on = Exceptions::MoveOn.new
    pending.each_key do |f|
      f.when_done do
        pending.delete(f)
        current.schedule if pending.empty?
      end
      f.schedule(move_on)
    end
    suspend until pending.empty?
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

  def wait_for_message
  end
end

module ChildFiberControl
  def children
    (@children ||= {}).keys
  end

  def spin(tag = nil, orig_caller = caller, &block)
    f = Fiber.new { |v| f.run(v) }
    f.setup(tag, block, orig_caller)
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

  def setup(tag, block, caller)
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
    Kernel.raise first_value if first_value.is_a?(Exception)

    start_execution(first_value)
  rescue Exceptions::MoveOn, Exceptions::Terminate => e
    finish_execution(e.value)
  rescue Exception => e
    finish_execution(e, true)
  end

  def start_execution(first_value)
    @running = true
    result = @block.(first_value)
    finish_execution(result)
  end

  def finish_execution(result, uncaught_exception = false)
    terminate_all_children
    await_all_children
    __fiber_trace__(:fiber_terminate, self, result)
    @result = result
    @running = false 
    @parent.child_done(self)
    @when_done_procs&.each { |p| p.(result) }
    @waiting_fibers&.each_key { |f| f.schedule(result) }
    return unless uncaught_exception && !@waiting_fibers

    # propagate unaught exception to parent
    @parent.schedule(result)
  ensure
    Thread.current.switch_fiber
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
