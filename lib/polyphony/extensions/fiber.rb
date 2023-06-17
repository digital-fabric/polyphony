# frozen_string_literal: true

require_relative '../core/exceptions'

# Fiber extensions
class ::Fiber
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

  #########################
  # Fiber control methods #
  #########################

  # Returns the fiber's monitoring mailbox queue, used for receiving fiber
  # monitoring messages.
  #
  # @return [Polyphony::Queue] monitoring mailbox queue
  def monitor_mailbox
    @monitor_mailbox ||= Polyphony::Queue.new
  end

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
  alias_method :kill, :interrupt
  alias_method :move_on, :interrupt

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

  # Raises an exception in the context of the fiber
  #
  # @overload fiber.raise(message)
  #   @param message [String] error message
  #   @return [Fiber] self
  # @overload fiber.raise(exception_class)
  #   @param exception_class [Class] exception class to raise
  #   @return [Fiber] self
  # @overload fiber.raise(exception_class, exception_message)
  #   @param exception_class [Class] exception class to raise
  #   @param exception_message [String] exception message to raise
  #   @return [Fiber] self
  # @overload fiber.raise(exception)
  #   @param any [Exception] exception to raise
  #   @return [Fiber] self
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

  #############################
  # Fiber supervision methods #
  #############################

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

  ###############################
  # Child fiber control methods #
  ###############################

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

  ############################
  # Fiber life cycle methods #
  ############################

  # Prepares a fiber for running.
  #
  # @param tag [any] fiber's tag
  # @param block [Proc] fiber's block
  # @param caller [Array<String>] fiber's caller
  # @param parent [Fiber] fiber's parent
  # @return [Fiber] self
  def prepare(tag, block, caller, parent)
    @thread = Thread.current
    @tag = tag
    @parent = parent
    @caller = caller
    @block = block
    Thread.backend.trace(:spin, self, Kernel.caller[1..-1])
    schedule
    self
  end

  # Runs the fiber's block and handles uncaught exceptions.
  #
  # @param first_value [any] value passed to fiber on first resume
  # @return [any] fiber result
  def run(first_value)
    Kernel.raise first_value if first_value.is_a?(Exception)
    @running = true

    Thread.backend.trace(:unblock, self, first_value, @caller)
    result = @block.(first_value)
    finalize(result)
    result
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
  # @return [Fiber] self
  def setup_raw
    @thread = Thread.current
    @running = true
    self
  end

  # Sets up the fiber as the main fiber for the current thread.
  #
  # @return [Fiber] self
  def setup_main_fiber
    @main = true
    @tag = :main
    @thread = Thread.current
    @running = true
    @children&.clear
    self
  end

  # Resets the fiber's state and reruns the fiber.
  #
  # @param first_value [Fiber] first_value to pass to fiber after restarting
  # @return [any] fiber result
  def restart_self(first_value)
    @mailbox = nil
    run(first_value)
  end

  # Finalizes the fiber, handling its return value or any uncaught exception.
  #
  # @param result [any] return value
  # @param uncaught_exception [Exception, nil] uncaught exception
  # @return [false]
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
  # @return [Array] array containing result and uncaught exception if any
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
  # @return [Fiber] self
  def inform_monitors(result, uncaught_exception)
    if @monitors
      msg = [self, result]
      @monitors.each_key { |f| f.monitor_mailbox << msg }
    end

    if uncaught_exception && @parent
      parent_is_monitor = @monitors&.has_key?(@parent)
      @parent.schedule_with_priority(result) unless parent_is_monitor
    end

    self
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

  class << self
    # Waits for all given fibers to terminate, then returns the respective
    # return values for all terminated fibers. If any of the awaited fibers
    # terminates with an uncaught exception, `Fiber.await` will await all the
    # other fibers to terminate, then reraise the exception.
    #
    # This method can be called with multiple fibers as multiple arguments, or
    # with a single array containing one or more fibers.
    #
    # @overload Fiber.await(f1, f2, ...)
    #   @param fibers [Array<Fiber>] fibers to wait for
    #   @return [Array<any>] return values of given fibers
    # @overload Fiber.await(fibers)
    #   @param fibers [Array<Fiber>] fibers to wait for
    #   @return [Array<any>] return values of given fibers
    def await(*fibers)
      return [] if fibers.empty?

      if (first = fibers.first).is_a?(Array)
        fibers = first
      end

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

Fiber.current.setup_main_fiber
