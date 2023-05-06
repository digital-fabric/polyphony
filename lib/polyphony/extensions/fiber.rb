# frozen_string_literal: true

require_relative '../core/exceptions'

module Polyphony

  # Fiber control methods
  module FiberControl
    # Returns the fiber's monitoring mailbox queue, used for receiving fiber
    # monitoring messages.
    #
    # @return [Polyphony::Queue] monitoring mailbox queue
    def monitor_mailbox
      @monitor_mailbox ||= Polyphony::Queue.new
    end

    # call-seq:
    #   fiber.stop(value = nil) -> fiber
    #   Fiber.interrupt(value = nil) -> fiber
    #   Fiber.move_on(value = nil) -> fiber
    #
    # Stops the fiber by raising a `Polyphony::MoveOn` exception. The given
    # value will become the fiber's return value.
    #
    # @param value [any] fiber's eventual return value
    # @return [Fiber] self
    def interrupt(value = nil)
      return if @running == false

      schedule Polyphony::MoveOn.new(value)
      self
    end
    alias_method :stop, :interrupt
    alias_method :move_on, :interrupt

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
    # @return [Fiber] self
    def cancel(exception = Polyphony::Cancel)
      return if @running == false

      value = (Class === exception) ? exception.new : exception
      schedule value
      self
    end

    # Sets the graceful shutdown flag for the fiber.
    #
    # @param graceful [bool] Whether or not to perform a graceful shutdown
    # @return [bool] graceful
    def graceful_shutdown=(graceful)
      @graceful_shutdown = graceful
    end

    # Returns the graceful shutdown flag for the fiber.
    #
    # @return [bool] true if graceful shutdown, otherwise false
    def graceful_shutdown?
      @graceful_shutdown
    end

    # Terminates the fiber, optionally setting the graceful shutdown flag.
    #
    # @param graceful [bool] Whether to perform a graceful shutdown
    # @return [Fiber] self
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
    # Raises an exception in the context of the fiber
    #
    # @return [Fiber] self
    def raise(*args)
      error = error_from_raise_args(args)
      schedule(error)
      self
    end

    # Adds an interjection to the fiber. The current operation undertaken by the
    # fiber will be interrupted, and the given block will be executed, and the
    # operation will be resumed. This API is experimental and might be removed
    # in the future.
    #
    # @yield [any] given block
    # @return [Fiber] self
    def interject(&block)
      raise Polyphony::Interjection.new(block)
    end

    # Blocks until the fiber has terminated, returning its return value.
    #
    # @return [any] fiber's return value
    def await
      Fiber.await(self).first
    end
    alias_method :join, :await

    private

    # @!visibility private
    def error_from_raise_args(args)
      case (arg = args.shift)
      when String then RuntimeError.new(arg)
      when Class  then arg.new(args.shift)
      when Exception then arg
      else RuntimeError.new
      end
    end
  end

  # Fiber supervision methods
  module FiberSupervision

    # call-seq:
    #   fiber.supervise
    #   fiber.supervise(fiber_a, fiber_b)
    #   fiber.supervise { |f, r| handle_terminated_fiber(f, r) }
    #   fiber.supervise(on_done: ->(f, r) { handle_terminated_fiber(f, r) })
    #   fiber.supervise(on_error: ->(f, e) { handle_error(f, e) })
    #   fiber.supervise(*fibers, restart: always)
    #   fiber.supervise(*fibers, restart: on_error)
    #
    # Supervises the given fibers or all child fibers. The fiber is put in
    # supervision mode, which means any child added after calling `#supervise`
    # will automatically be supervised. Depending on the given options, fibers
    # may be automatically restarted.
    #
    # If a block is given, the block is called whenever a supervised fiber has
    # terminated. If the `:on_done` option is given, that proc will be called
    # when a supervised fiber has terminated. If the `:on_error` option is
    # given, that proc will be called when a supervised fiber has terminated
    # with an uncaught exception. If the `:restart` option equals `:always`,
    # fibers will always be restarted. If the `:restart` option equals
    # `:on_error`, fibers will be restarted only when terminated with an
    # uncaught exception.
    #
    # This method blocks indefinitely.
    #
    # @param fibers [Array<Fiber>] fibers to supervise
    # @option opts [Proc, nil] :on_done proc to call when a supervised fiber is terminated
    # @option opts [Proc, nil] :on_error proc to call when a supervised fiber is terminated with an exception
    # @option opts [:always, :on_error, nil] :restart whether to restart terminated fibers
    # @yield [] supervisor block
    # @return [void]
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

    private

    # @!visibility private
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

  # Fiber control class methods
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
    # @param fibers [Array<Fiber>] fibers to wait for
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
    # @param fibers [Array<Fiber>] Fibers to wait for
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
    #
    # @yield [] given block
    # @return [void]
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

    private

    # @!visibility private
    def prepare_oob_fiber(fiber, block)
      fiber.oob = true
      fiber.tag = :oob
      fiber.thread = Thread.current
      location = block.source_location
      fiber.set_caller(["#{location.join(':')}"])
    end
  end

  # Child fiber control methods
  module ChildFiberControl

    # Returns the fiber's children.
    #
    # @return [Array<Fiber>] child fibers
    def children
      (@children ||= {}).keys
    end

    # Creates a new child fiber.
    #
    #   child = fiber.spin { sleep 10; fiber.stop }
    #
    # @param tag [any] child fiber's tag
    # @param orig_caller [Array<String>] caller to set for fiber
    # @yield [any] child fiber's block
    # @return [Fiber] child fiber
    def spin(tag = nil, orig_caller = Kernel.caller, &block)
      f = Fiber.new { |v| f.run(v) }
      f.prepare(tag, block, orig_caller, self)
      (@children ||= {})[f] = true
      f.monitor(self) if @supervise_mode
      f
    end

    # Terminates all child fibers. This method will return before the fibers are
    # actually terminated.
    #
    # @param graceful [bool] whether to perform a graceful termination
    # @return [Fiber] self
    def terminate_all_children(graceful = false)
      return self unless @children

      e = Polyphony::Terminate.new
      @children.each_key do |c|
        c.graceful_shutdown = true if graceful
        c.raise e
      end
      self
    end

    # Block until all child fibers have terminated. Returns the return values
    # for all child fibers.
    #
    # @return [Array<any>] return values of child fibers
    def await_all_children
      return unless @children && !@children.empty?

      Fiber.await(*@children.keys.reject { |c| c.dead? })
    end

    # Terminates and blocks until all child fibers have terminated.
    #
    # @return [Fiber] self
    def shutdown_all_children(graceful = false)
      return self unless @children

      pending = []
      @children.keys.each do |c|
        next if c.dead?

        c.terminate(graceful)
        pending << c
      end
      Fiber.await(*pending)
      self
    end

    # Attaches all child fibers to a new parent.
    #
    # @param parent [Fiber] new parent
    # @return [Fiber] self
    def attach_all_children_to(parent)
      @children&.keys.each { |c| c.attach_to(parent) }
      self
    end

    # Detaches the fiber from its current parent. The fiber will be made a child
    # of the main fiber (for the current thread.)
    #
    # @return [Fiber] self
    def detach
      @parent.remove_child(self)
      @parent = @thread.main_fiber
      @parent.add_child(self)
      self
    end

    # Attaches the fiber to a new parent.
    #
    # @param parent [Fiber] new parent
    # @return [Fiber] self
    def attach_to(parent)
      @parent.remove_child(self)
      @parent = parent
      parent.add_child(self)
      self
    end

    # Attaches the fiber to the new parent and monitors the new parent.
    #
    # @param parent [Fiber] new parent
    # @return [Fiber] self
    def attach_and_monitor(parent)
      @parent.remove_child(self)
      @parent = parent
      parent.add_child(self)
      monitor(parent)
      self
    end

    # Adds a child fiber reference. Used internally.
    #
    # @param child_fiber [Fiber] child fiber
    # @return [Fiber] self
    def add_child(child_fiber)
      (@children ||= {})[child_fiber] = true
      child_fiber.monitor(self) if @supervise_mode
      self
    end

    # Removes a child fiber reference. Used internally.
    #
    # @param child_fiber [Fiber] child fiber to be removed
    # @return [Fiber] self
    def remove_child(child_fiber)
      @children.delete(child_fiber) if @children
      self
    end
  end

  # Fiber life cycle methods
  module FiberLifeCycle

    # Prepares a fiber for running.
    #
    # @param tag [any] fiber's tag
    # @param block [Proc] fiber's block
    # @param caller [Array<String>] fiber's caller
    # @param parent [Fiber] fiber's parent
    # @return [void]
    def prepare(tag, block, caller, parent)
      @thread = Thread.current
      @tag = tag
      @parent = parent
      @caller = caller
      @block = block
      Thread.backend.trace(:spin, self, Kernel.caller[1..-1])
      schedule
    end

    # Runs the fiber's block and handles uncaught exceptions.
    #
    # @param first_value [any] value passed to fiber on first resume
    # @return [void]
    def run(first_value)
      Kernel.raise first_value if first_value.is_a?(Exception)
      @running = true

      Thread.backend.trace(:unblock, self, first_value, @caller)
      result = @block.(first_value)
      finalize(result)
    rescue Polyphony::Restart => e
      restart_self(e.value)
    rescue Polyphony::MoveOn, Polyphony::Terminate => e
      finalize(e.value)
    rescue Exception => e
      e.source_fiber = self
      finalize(e, true)
    end

    # Performs setup for a "raw" Fiber created using Fiber.new. Note that this
    # fiber is an orphan fiber (has no parent), since we cannot control how the
    # fiber terminates after it has already been created. Calling #setup_raw
    # allows the fiber to be scheduled and to receive messages.
    #
    # @return [void]
    def setup_raw
      @thread = Thread.current
      @running = true
    end

    # Sets up the fiber as the main fiber for the current thread.
    #
    # @return [void]
    def setup_main_fiber
      @main = true
      @tag = :main
      @thread = Thread.current
      @running = true
      @children&.clear
    end

    # Resets the fiber's state and reruns the fiber.
    #
    # @param first_value [Fiber] first_value to pass to fiber after restarting
    # @return [void]
    def restart_self(first_value)
      @mailbox = nil
      run(first_value)
    end

    # Finalizes the fiber, handling its return value or any uncaught exception.
    #
    # @param result [any] return value
    # @param uncaught_exception [Exception, nil] uncaught exception
    # @return [void]
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
    #
    # @param result [any] fiber's return value
    # @param uncaught_exception [Exception, nil] uncaught exception
    # @return [void]
    def finalize_children(result, uncaught_exception)
      shutdown_all_children(graceful_shutdown?)
      [result, uncaught_exception]
    rescue Exception => e
      [e, true]
    end

    # Informs the fiber's monitors it is terminated.
    #
    # @param result [any] fiber's return value
    # @param uncaught_exception [Exception, nil] uncaught exception
    # @return [void]
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

    # Adds a fiber to the list of monitoring fibers. Monitoring fibers will be
    # notified on their monitor mailboxes when the fiber is terminated.
    #
    # @param fiber [Fiber] monitoring fiber
    # @return [Fiber] self
    def monitor(fiber)
      (@monitors ||= {})[fiber] = true
      self
    end

    # Removes a monitor fiber.
    #
    # @param fiber [Fiber] monitoring fiber
    # @return [Fiber] self
    def unmonitor(fiber)
      (@monitors ||= []).delete(fiber)
      self
    end

    # Returns the list of monitoring fibers.
    #
    # @return [Array<Fiber>] monitoring fibers
    def monitors
      @monitors&.keys || []
    end

    # Returns true if the fiber is dead.
    #
    # @return [bool] is fiber dead
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

  # Returns true if fiber is running.
  #
  # @return [bool] is fiber running
  def running?
    @running
  end

  # Returns a string representation of the fiber for debugging.
  #
  # @return [String] string representation
  def inspect
    if @tag
      "#<Fiber #{tag}:#{object_id} #{location} (#{state})>"
    else
      "#<Fiber:#{object_id} #{location} (#{state})>"
    end
  end
  alias_method :to_s, :inspect

  # Returns the source location for the fiber based on its caller.
  #
  # @return [String] source location
  def location
    if @oob
      "#{@caller[0]} (oob)"
    else
      @caller ? @caller[0] : '(root)'
    end
  end

  # Returns the fiber's caller.
  #
  # @return [Array<String>] caller
  def caller
    spin_caller = @caller || []
    if @parent
      spin_caller + @parent.caller
    else
      spin_caller
    end
  end

  # Sets the fiber's caller.
  #
  # @param caller [Array<String>] new caller
  # @return [Fiber] self
  def set_caller(caller)
    @caller = caller
    self
  end

  # Returns true if the fiber is the main fiber for its thread.
  #
  # @return [bool] is main fiber
  def main?
    @main
  end
end

Fiber.current.setup_main_fiber
