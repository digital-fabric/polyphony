# frozen_string_literal: true

export :Group

# Based on code in the timers gem:
#   https://github.com/socketry/timers

# Maintains a group of timers to be used in a reactor
class Group
  # Initializes the list of timers, and the last timer id
  def initialize
    @timers = []
    @cancelled = []
    @last_id = 0
  end

  # Returns true if group has no timers
  # @return [Boolean] is group empty
  def empty?
    @timers.empty?
  end

  # Adds a one-shot timer
  # @param timeout [Float] timeout in seconds
  # @return [Integer] timer id
  def timeout(timeout, &block)
    schedule(
      id: (@last_id += 1),
      stamp: now + timeout,
      block: block
    )
    @last_id
  end

  # Adds a recurring timer
  # @param span [Float] interval in seconds
  # @return [Integer] timer id
  def interval(interval, &block)
    schedule(
      id: (@last_id += 1),
      stamp: now + interval,
      interval: interval,
      block: block
    )
    @last_id
  end

  # Cancels a pending timer
  # @param id [Integer] timer id
  # @return [void]
  def cancel(id)
    @timers.reject! { |t| t[:id] == id }
    @cancelled << id
  end

  def cancel_all
    @cancelled += @timers
    @timers.clear
  end

  # Returns time interval until next scheduled timer
  # @return [Float] time left until next scheduled timer
  def idle_interval
    return nil unless (first = @timers.last)

    interval = first[:stamp] - now
    interval.negative? ? 0 : interval
  end

  # Fires all elapsed timers
  # @return [void]
  def fire
    # clear @cancelled, which is used to track timers cancelled while looping
    # over elapsed timers, in order to prevent race condition
    @cancelled.clear
    pop(now).reverse_each do |t|
      next if @cancelled.include?(t[:id])
      t[:block].(t[:id])
      if t[:interval]
        t[:stamp] += t[:interval]
        schedule(t)
      end
    end
  end

  private

  # Schedules a timer at the given time, inserting it into a reverse-ordered
  # list of timers (last item is first to be fired)
  # @param timer [Hash] timer spec
  # @return [void]
  def schedule(timer)
    index = stamp_index(timer[:stamp])
    @timers.insert(index, timer)
  end

  # Pop all timers occurring before the given stamp from the list of pending
  # timers
  # @param stamp [Float] threshold stamp
  # @return [Array<Hash>] array of timers
  def pop(stamp)
    index = stamp_index(stamp)
    @timers.pop(@timers.size - index)
  end

  # Returns the index at which to insert the given element
  # @param stamp [Float] stamp
  # @return [Integer] index in timers array
  def stamp_index(stamp)
    lower = 0
    upper = @timers.length
    while lower < upper
      middle = lower + (upper - lower).div(2)
      @timers[middle][:stamp] > stamp ? (lower = middle + 1) : (upper = middle)
    end

    lower
  end

  # Returns current time stamp based on CPU monotonic clock
  # @return [Float] current processor clock stamp as float
  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
