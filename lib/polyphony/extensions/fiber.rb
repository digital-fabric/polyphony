# frozen_string_literal: true

require_relative '../core/exceptions'

module Polyphony
  # Fiber control API
  module FiberControl
    # Returns the fiber's monitoring mailbox queue, used for receiving fiber
    # monitoring messages.
    #
    # @return [Polyphony::Queue] Monitoring mailbox queue
    def monitor_mailbox
      @monitor_mailbox ||= Polyphony::Queue.new
    end

    # call-seq:
    #   fiber.stop(value = nil) -> fiber
    #   Fiber.interrupt(value = nil) -> fiber
    #
    # Stops the fiber by raising a Polyphony::MoveOn exception. The given value
    # will become the fiber's return value.
    #
    # @param value [any] Fiber's eventual return value
    # @return [Fiber] fiber
    def interrupt(value = nil)
      return if @running == false

      schedule Polyphony::MoveOn.new(value)
      self
    end
    alias_method :stop, :interrupt

    # call-seq:
    #   fiber.reset(value = nil) -> fiber
    #   fiber.restart(value = nil) -> fiber
    #
    # Restarts the fiber, with the given value serving as the first value passed
    # to the fiber's block.
    #
    # @param value [any] value passed to fiber block
    # @return [Fiber] restarted fiber
    def restart(value = nil)
      raise "Can't restart main fiber" if @main

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

    # Stops a fiber by raising a Polyphony::Cancel exception.
    #
    # @param exception [Class, Exception] exception or exception class
    # @return [Fiber] fiber
    def cancel(exception = Polyphony::Cancel)
      return if @running == false

      value = (Class === exception) ? exception.new : exception
      schedule value
      self
    end

    # Sets the graceful shutdown flag for the fiber.
    #
    # @param graceful [bool] Whether or not to perform a graceful shutdown
    def graceful_shutdown=(graceful)
      @graceful_shutdown = graceful
    end

    # Returns the graceful shutdown flag for the fiber.
    #
    # @return [bool]
    def graceful_shutdown?
      @graceful_shutdown
    end

    # Terminates the fiber, optionally setting the graceful shutdown flag.
    #
    # @param graceful [bool] Whether to perform a graceful shutdown
    # @return [Fiber]
    def terminate(graceful = false)
      return if @running == false

      @graceful_shutdown = graceful
      schedule Polyphony::Terminate.new
      self
    end

    # call-seq:
    #   fiber.raise(message) -> fiber
    #   fiber.raise(exception_class) -> fiber
    #   fiber.raise(exception_class, exception_message) -> fiber
    #   fiber.raise(exception) -> fiber
    #
    # Raises an exception in the context of the fiber.
    #
    # @return [Fiber]
    def raise(*args)
      error = error_from_raise_args(args)
      schedule(error)
      self
    end

    # :no-doc:
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
      block ||= supervise_opts_to_block(opts)

      @supervise_mode = true
      fibers = children if fibers.empty?
      fibers.each do |f|
        f.attach_to(self) unless f.parent == self
        f.monitor(self)
      end

      mailbox = monitor_mailbox

      while true
        (fiber, result) = mailbox.shift
        block&.call(fiber, result)
      end
    ensure
      @supervise_mode = false
    end

    def supervise_opts_to_block(opts)
      block = opts[:on_done] || opts[:on_error]
      restart = opts[:restart]
      return nil unless block || restart

      error_only = !!opts[:on_error]
      restart_always = (restart == :always) || (restart == true)
      restart_on_error = restart == :on_error

      ->(f, r) do
        is_error = r.is_a?(Exception)
        block.(f, r) if block && (!error_only || is_error)
        f.restart if restart_always || (restart_on_error && is_error)
      end
    end
  end

  # Class methods for controlling fibers (namely await and select)
  module FiberControlClassMethods
    # call-seq:
    #   Fiber.await(*fibers) -> [*results]
    #   Fiber.join(*fibers) -> [*results]
    #
    # Waits for all given fibers to terminate, then returns the respective
    # return values for all terminated fibers. If any of the awaited fibers
    # terminates with an uncaught exception, `Fiber.await` will await all the
    # other fibers to terminate, then reraise the exception.
    #
    # @param *fibers [Array<Fiber>] fibers to wait for
    # @return [Array<any>] return values of given fibers
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

    # Waits for at least one of the given fibers to terminate, returning an
    # array containing the first terminated fiber and its return value. If an
    # exception occurs in one of the given fibers, it will be reraised.
    #
    # @param *fibers [Array<Fiber>] Fibers to wait for
    # @return [Array] Array containing the first terminated fiber and its return value
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
      oob_fiber = Fiber.new do
        Fiber.current.setup_raw
        Thread.backend.trace(:unblock, oob_fiber, nil, @caller)
        result = block.call
      rescue Exception => e
        Thread.current.schedule_and_wakeup(Thread.main.main_fiber, e)
        result = e
      ensure
        Thread.backend.trace(:terminate, Fiber.current, result)
        suspend
      end
      prepare_oob_fiber(oob_fiber, block)
      Thread.backend.trace(:spin, oob_fiber, caller)
      oob_fiber.schedule_with_priority(nil)
    end

    def prepare_oob_fiber(fiber, block)
      fiber.oob = true
      fiber.tag = :oob
      fiber.thread = Thread.current
      location = block.source_location
      fiber.set_caller(["#{location.join(':')}"])
    end
  end

  # Methods for controlling child fibers
  module ChildFiberControl
    def children
      (@children ||= {}).keys
    end

    def add_child(child_fiber)
      (@children ||= {})[child_fiber] = true
      child_fiber.monitor(self) if @supervise_mode
    end

    def remove_child(child_fiber)
      @children.delete(child_fiber) if @children
    end

    def spin(tag = nil, orig_caller = Kernel.caller, &block)
      f = Fiber.new { |v| f.run(v) }
      f.prepare(tag, block, orig_caller, self)
      (@children ||= {})[f] = true
      f.monitor(self) if @supervise_mode
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
    end

    def attach_all_children_to(fiber)
      @children&.keys.each { |c| c.attach_to(fiber) }
    end

    def detach
      @parent.remove_child(self)
      @parent = @thread.main_fiber
      @parent.add_child(self)
      self
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
      Thread.backend.trace(:spin, self, Kernel.caller[1..-1])
      schedule
    end

    def run(first_value)
      setup first_value
      Thread.backend.trace(:unblock, self, first_value, @caller)
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
      Thread.backend.trace(:terminate, self, result)
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
      shutdown_all_children(graceful_shutdown?)
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

  attr_accessor :tag, :thread, :parent, :oob
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
    if @oob
      "#{@caller[0]} (oob)"
    else
      @caller ? @caller[0] : '(root)'
    end
  end

  def caller
    spin_caller = @caller || []
    if @parent
      spin_caller + @parent.caller
    else
      spin_caller
    end
  end

  def set_caller(o)
    @caller = o
  end

  def main?
    @main
  end
end

Fiber.current.setup_main_fiber
