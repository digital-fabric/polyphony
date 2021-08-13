# frozen_string_literal: true

require 'fiber'

require_relative '../core/exceptions'

module Polyphony
  # Fiber control API
  module FiberControl
    def monitor_mailbox
      @monitor_mailbox ||= Polyphony::Queue.new
    end

    def interrupt(value = nil)
      return if @running == false

      schedule Polyphony::MoveOn.new(value)
    end
    alias_method :stop, :interrupt

    def restart(value = nil)
      raise "Can''t restart main fiber" if @main

      if @running
        schedule Polyphony::Restart.new(value)
        return self
      end

      fiber = parent.spin(@tag, @caller, &@block)
      @monitors&.each_key { |f| fiber.monitor(f) }
      fiber.schedule(value) unless value.nil?
      fiber
    end
    alias_method :reset, :restart

    def cancel
      return if @running == false

      schedule Polyphony::Cancel.new
    end

    def graceful_shutdown=(graceful)
      @graceful_shutdown = graceful
    end

    def graceful_shutdown?
      @graceful_shutdown
    end

    def terminate(graceful = false)
      return if @running == false

      @graceful_shutdown = graceful
      schedule Polyphony::Terminate.new
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

    def interject(&block)
      raise Polyphony::Interjection.new(block)
    end

    def await
      Fiber.await(self).first
    end
    alias_method :join, :await
  end

  # Fiber supervision
  module FiberSupervision
    def supervise(*fibers, **opts, &block)
      block ||= opts[:on_done] ||
                (opts[:on_error] && supervise_on_error_proc(opts[:on_error]))
      raise "No block given" unless block

      fibers.each do |f|
        f.attach_to(self) unless f.parent == self
        f.monitor(self)
      end

      mailbox = monitor_mailbox

      while true
        (fiber, result) = mailbox.shift
        block&.call(fiber, result)
      end
    end

    def supervise_on_error_proc(on_error)
      ->(f, r) { on_error.(f, r) if r.is_a?(Exception) }
    end
  end

  # Class methods for controlling fibers (namely await and select)
  module FiberControlClassMethods
    def await(*fibers)
      return [] if fibers.empty?

      current_fiber = self.current
      mailbox = current_fiber.monitor_mailbox
      results = {}
      fibers.each do |f|
        results[f] = nil
        if f.dead?
          # fiber already terminated, so queue message
          mailbox << [f, f.result]
        else
          f.monitor(current_fiber)
        end
      end
      exception = nil
      while !fibers.empty?
        (fiber, result) = mailbox.shift
        next unless fibers.include?(fiber)
        fibers.delete(fiber)
        current_fiber.remove_child(fiber) if fiber.parent == current_fiber
        if result.is_a?(Exception)
          exception ||= result
          fibers.each { |f| f.terminate }
        else
          results[fiber] = result
        end
      end
      raise exception if exception
      results.values
    end
    alias_method :join, :await

    def select(*fibers)
      return nil if fibers.empty?
  
      current_fiber = self.current
      mailbox = current_fiber.monitor_mailbox
      fibers.each do |f|
        if f.dead?
          result = f.result
          result.is_a?(Exception) ? (raise result) : (return [f, result])
        end
      end

      fibers.each { |f| f.monitor(current_fiber) }
      while true
        (fiber, result) = mailbox.shift
        next unless fibers.include?(fiber)
  
        fibers.each { |f| f.unmonitor(current_fiber) }
        if result.is_a?(Exception)
          raise result
        else
          return [fiber, result]
        end
      end
    end

    # Creates and schedules with priority an out-of-band fiber that runs the
    # supplied block. If any uncaught exception is raised while the fiber is
    # running, it will bubble up to the main thread's main fiber, which will
    # also be scheduled with priority. This method is mainly used trapping
    # signals (see also the patched `Kernel#trap`)
    def schedule_priority_oob_fiber(&block)
      f = Fiber.new do
        Fiber.current.setup_raw
        block.call
      rescue Exception => e
        Thread.current.schedule_and_wakeup(Thread.main.main_fiber, e)
      end
      Thread.current.schedule_and_wakeup(f, nil)
    end
  end

  # Methods for controlling child fibers
  module ChildFiberControl
    def children
      (@children ||= {}).keys
    end

    def add_child(child_fiber)
      (@children ||= {})[child_fiber] = true
    end

    def remove_child(child_fiber)
      @children.delete(child_fiber) if @children
    end

    def spin(tag = nil, orig_caller = Kernel.caller, &block)
      f = Fiber.new { |v| f.run(v) }
      f.prepare(tag, block, orig_caller, self)
      (@children ||= {})[f] = true
      f
    end

    def terminate_all_children(graceful = false)
      return unless @children

      e = Polyphony::Terminate.new
      @children.each_key do |c|
        c.graceful_shutdown = true if graceful
        c.raise e
      end
    end

    def await_all_children
      return unless @children && !@children.empty?

      Fiber.await(*@children.keys.reject { |c| c.dead? })
    end

    def shutdown_all_children(graceful = false)
      return unless @children

      @children.keys.each do |c|
        next if c.dead?

        c.terminate(graceful)
        c.await
      end
      reap_dead_children
    end

    def reap_dead_children
      return unless @children

      @children.reject! { |f| f.dead? }
    end

    def detach
      @parent.remove_child(self)
      @parent = @thread.main_fiber
      @parent.add_child(self)
    end

    def attach_to(fiber)
      @parent.remove_child(self)
      @parent = fiber
      fiber.add_child(self)
    end

    def attach_and_monitor(fiber)
      @parent.remove_child(self)
      @parent = fiber
      fiber.add_child(self)
      monitor(fiber)
    end
  end

  # Fiber life cycle methods
  module FiberLifeCycle
    def prepare(tag, block, caller, parent)
      @thread = Thread.current
      @tag = tag
      @parent = parent
      @caller = caller
      @block = block
      Thread.backend.trace(:fiber_create, self)
      schedule
    end

    def run(first_value)
      setup first_value
      result = @block.(first_value)
      finalize result
    rescue Polyphony::Restart => e
      restart_self(e.value)
    rescue Polyphony::MoveOn, Polyphony::Terminate => e
      finalize e.value
    rescue Exception => e
      e.source_fiber = self
      finalize e, true
    end

    def setup(first_value)
      Kernel.raise first_value if first_value.is_a?(Exception)

      @running = true
    end

    # Performs setup for a "raw" Fiber created using Fiber.new. Note that this
    # fiber is an orphan fiber (has no parent), since we cannot control how the
    # fiber terminates after it has already been created. Calling #setup_raw
    # allows the fiber to be scheduled and to receive messages.
    def setup_raw
      @thread = Thread.current
      @running = true
    end

    def setup_main_fiber
      @main = true
      @tag = :main
      @thread = Thread.current
      @running = true
      @children&.clear
    end

    def restart_self(first_value)
      @mailbox = nil
      run(first_value)
    end

    def finalize(result, uncaught_exception = false)
      result, uncaught_exception = finalize_children(result, uncaught_exception)
      Thread.backend.trace(:fiber_terminate, self, result)
      @result = result

      inform_monitors(result, uncaught_exception)
      @running = false
    ensure
      @parent&.remove_child(self)
      # Prevent fiber from being resumed after terminating
      @thread.fiber_unschedule(self)
      Thread.current.switch_fiber
    end

    # Shuts down all children of the current fiber. If any exception occurs while
    # the children are shut down, it is returned along with the uncaught_exception
    # flag set. Otherwise, it returns the given arguments.
    def finalize_children(result, uncaught_exception)
      shutdown_all_children
      [result, uncaught_exception]
    rescue Exception => e
      [e, true]
    end

    def inform_monitors(result, uncaught_exception)
      if @monitors
        msg = [self, result]
        @monitors.each_key { |f| f.monitor_mailbox << msg }
      end

      if uncaught_exception && @parent
        parent_is_monitor = @monitors&.has_key?(@parent)
        @parent.schedule_with_priority(result) unless parent_is_monitor
      end
    end

    def monitor(fiber)
      (@monitors ||= {})[fiber] = true
    end

    def unmonitor(fiber)
      (@monitors ||= []).delete(fiber)
    end

    def monitors
      @monitors&.keys || []
    end

    def dead?
      state == :dead
    end
  end
end

# Fiber extensions
class ::Fiber
  prepend Polyphony::FiberControl
  include Polyphony::FiberSupervision
  include Polyphony::ChildFiberControl
  include Polyphony::FiberLifeCycle

  extend Polyphony::FiberControlClassMethods

  attr_accessor :tag, :thread, :parent
  attr_reader :result

  def running?
    @running
  end

  def inspect
    if @tag
      "#<Fiber #{tag}:#{object_id} #{location} (#{state})>"
    else
      "#<Fiber:#{object_id} #{location} (#{state})>"
    end
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
