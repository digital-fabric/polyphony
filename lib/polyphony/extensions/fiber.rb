# frozen_string_literal: true

require 'fiber'

require_relative '../core/exceptions'

module Polyphony
  # Fiber control API
  module FiberControl
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

      parent.spin(@tag, @caller, &@block).tap do |f|
        f.schedule(value) unless value.nil?
      end
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
  end

  # Fiber supervision
  module FiberSupervision
    def supervise(opts = {})
      @counter = 0
      @on_child_done = proc do |fiber, result|
        self << fiber unless result.is_a?(Exception)
      end
      while true
        supervise_perform(opts)
      end
    rescue Polyphony::MoveOn
      # generated in #supervise_perform to stop supervisor
    ensure
      @on_child_done = nil
    end

    def supervise_perform(opts)
      fiber = receive
      if fiber && opts[:restart]
        restart_fiber(fiber, opts)
      elsif Fiber.current.children.empty?
        Fiber.current.stop
      end
    rescue Polyphony::Restart
      restart_all_children
    rescue Exception => e
      Kernel.raise e if e.source_fiber.nil? || e.source_fiber == self

      if opts[:restart]
        restart_fiber(e.source_fiber, opts)
      elsif Fiber.current.children.empty?
        Fiber.current.stop
      end
    end

    def restart_fiber(fiber, opts)
      opts[:watcher]&.send [:restart, fiber]
      case opts[:restart]
      when true
        fiber.restart
      when :one_for_all
        @children.keys.each(&:restart)
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
      await_select_cleanup(state) if state
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

      terminate = Polyphony::Terminate.new
      state[:cleanup] = true
      state[:pending].each_key { |f| f.schedule(terminate) }
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

    def child_done(child_fiber, result)
      @children.delete(child_fiber)
      @on_child_done&.(child_fiber, result)
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

      results = @children.dup
      @on_child_done = proc do |c, r|
        results[c] = r
        schedule if @children.empty?
      end
      suspend
      @on_child_done = nil
      results.values
    end

    def shutdown_all_children(graceful = false)
      return unless @children

      @children.keys.each do |c|
        c.terminate(graceful)
        c.await
      end
    end

    def detach
      @parent.remove_child(self)
      @parent = @thread.main_fiber
      @parent.add_child(self)
    end

    def attach(parent)
      @parent.remove_child(self)
      @parent = parent
      @parent.add_child(self)
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
      @when_done_procs = nil
      @waiting_fibers = nil
      run(first_value)
    end

    def finalize(result, uncaught_exception = false)
      result, uncaught_exception = finalize_children(result, uncaught_exception)
      Thread.backend.trace(:fiber_terminate, self, result)
      @result = result
      @running = false
      inform_dependants(result, uncaught_exception)
    ensure
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

    def inform_dependants(result, uncaught_exception)
      @parent&.child_done(self, result)
      @when_done_procs&.each { |p| p.(result) }
      @waiting_fibers&.each_key { |f| f.schedule(result) }
      
      # propagate unaught exception to parent
      @parent&.schedule_with_priority(result) if uncaught_exception && !@waiting_fibers
    end

    def when_done(&block)
      @when_done_procs ||= []
      @when_done_procs << block
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
