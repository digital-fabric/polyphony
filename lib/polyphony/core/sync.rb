# frozen_string_literal: true

require 'monitor'

module Polyphony
  # Implements mutex lock for synchronizing access to a shared resource. This
  # class replaces the stock `Thread::Mutex` class.
  class Mutex
    # Initializes a new mutex.
    def initialize
      @store = Queue.new
      @store << :token
    end

    # Locks the mutex, runs the block, then unlocks it.
    #
    # This method is re-entrant. Recursive calls from the given block will not
    # block.
    #
    # @return [any] return value of block
    def synchronize(&block)
      return yield if @holding_fiber == Fiber.current

      synchronize_not_holding(&block)
    end

    # Conditionally releases the mutex. This method is used by condition
    # variables.
    #
    # @return [nil]
    def conditional_release
      @store << @token
      @token = nil
      @holding_fiber = nil
    end

    # Conditionally reacquires the mutex. This method is used by condition
    # variables.
    #
    # @return [Fiber] current fiber
    def conditional_reacquire
      @token = @store.shift
      @holding_fiber = Fiber.current
    end

    # Returns the fiber currently owning the mutex.
    #
    # @return [Fiber, nil] current owner or nil
    def owned?
      @holding_fiber == Fiber.current
    end

    # Returns a truthy value if the mutex is currently locked.
    #
    # @return [any] truthy if fiber is currently locked
    def locked?
      @holding_fiber
    end

    # Obtains a lock. Raises `ThreadError` if mutex is locked by the current
    # thread.
    #
    # @return [Mutex] self
    def lock
      check_dead_holder
      raise ThreadError if owned?

      @token = @store.shift
      @holding_fiber = Fiber.current
      self
    end

    # Releases the lock. Raises `ThreadError` if mutex is not locked by the
    # current thread.
    #
    # @return [Mutex] self
    def unlock
      raise ThreadError if !owned?

      @holding_fiber = nil
      @store << @token if @token
      @token = nil
    end

    # Attempts to obtain the lock and returns immediately. Returns `true` if the
    # lock was granted.
    #
    # @return [true, false]
    def try_lock
      return false if @holding_fiber

      @token = @store.shift
      @holding_fiber = Fiber.current
      true
    end

    # Releases the lock and sleeps timeout seconds if it is given and non-nil or
    # forever. Raises `ThreadError` if mutex wasn’t locked by the current
    # thread.
    #
    # @param timeout [nil, Number] sleep timeout
    # @return [Number] slept time in seconds
    def sleep(timeout = nil)
      unlock
      t0 = Time.now
      Kernel.sleep(timeout)
      t1 = Time.now
      lock

      return t1 - t0
    end

    private

    # Helper method for performing a `#synchronize` when not currently holding
    # the mutex.
    #
    # @return [any] return value of given block.
    def synchronize_not_holding
      @token = @store.shift
      begin
        @holding_fiber = Fiber.current
        yield
      ensure
        @holding_fiber = nil
        @store << @token if @token
        @token = nil
      end
    end

    def check_dead_holder
      return if !@holding_fiber&.dead?

      @holding_fiber = nil
      @store << @token if @token
      @token = nil
    end
  end

  # Implements a fiber-aware Monitor class. This class replaces the stock
  # `Monitor` class.
  class Monitor < Mutex
    def enter
      if @holding_fiber == Fiber.current
        @holding_count += 1
      else
        lock
        @holding_count = 1
      end
    end
    alias_method :mon_enter, :enter

    def exit
      raise ThreadError if !owned?

      @holding_count -= 1
      unlock if @holding_count == 0
    end
    alias_method :mon_exit, :exit

    def mon_check_owner
      if Fiber.current == @holding_fiber
        nil
      else
        raise ThreadError, 'current fiber not owner'
      end
    end

    def mon_locked?
      !!@holding_fiber
    end

    def mon_owned?
      @holding_fiber == Fiber.current
    end

    alias_method :mon_synchronize, :synchronize

    def new_cond
      MonitorMixin::ConditionVariable.new(self)
    end

    def try_enter
      check_dead_holder
      return false if @holding_fiber

      enter
      true
    end
    alias_method :try_mon_enter, :try_enter

    def wait_for_cond(cond, timeout)
      cond.wait(self, timeout)
    end
  end

  # Implements a fiber-aware ConditionVariable
  class ConditionVariable
    # Initializes the condition variable.
    def initialize
      @queue = Polyphony::Queue.new
    end

    # Waits for the condition variable to be signalled.
    #
    # @param mutex [Polyphony::Mutex] mutex to release while waiting for signal
    # @param timeout [Number, nil] timeout in seconds, or nil for no timeout
    # @return [any]
    def wait(mutex, timeout = nil)
      mutex.conditional_release
      @queue << Fiber.current
      if timeout
        move_on_after(timeout, with_value: false) { Polyphony.backend_wait_event(true); true }
      else
        Polyphony.backend_wait_event(true)
        true
      end
    ensure
      mutex.conditional_reacquire
    end

    # Signals the condition variable, causing the first fiber in the waiting
    # queue to be resumed.
    #
    # @return [Fiber] resumed fiber
    def signal
      return if @queue.empty?

      fiber = @queue.shift
      fiber.schedule
    end

    # Resumes all waiting fibers.
    def broadcast
      return if @queue.empty?

      while (fiber = @queue.shift)
        fiber.schedule
      end
    end
  end
end
