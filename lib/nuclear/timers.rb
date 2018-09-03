# frozen_string_literal: true

export  :Group

# Based on code in the timers gem:
#   https://github.com/socketry/timers

# Maintains a group of timers to be used in a reactor
class Group
  # Initializes the list of timers, and the last timer id
  def initialize
    @timers = []
    @last_id = 0
  end

  # Returns true if group has no timers
  def empty?
    @timers.empty?
  end

  # Adds a one-shot timer
  def timeout(interval, &block)
    schedule(
      id: (@last_id += 1),
      stamp: Group.now + interval,
      block: block
    )
    @last_id
  end

  # Adds a recurring timer
  def interval(interval, &block)
    schedule(
      id: (@last_id += 1),
      stamp: Group.now + interval,
      interval: interval,
      block: block
    )
    @last_id
  end

  # Cancel a timer
  def cancel(id)
    @timers.reject! { |t| t[:id] == id }
  end

  # Returns time interval until next scheduled timer
  def idle_interval
    if (first = @timers.last)
      interval = first[:stamp] - Group.now
      interval < 0 ? 0 : interval
    end
  end

  # Fires all elapsed timers
  def fire
    pop(Group.now).reverse_each do |t|
      t[:block].(t[:id])
      if t[:interval]
        t[:stamp] += t[:interval]
        schedule(t)
      end
    end
  end

  private

  # Add a timer at the given time.
  def schedule(timer)
    index = bisect_left(@timers, timer[:stamp])
    @timers.insert(index, timer)
  end

  # Efficiently take k handles for which Handle#time is less than the given
  # time.
  def pop(stamp)
    index = bisect_left(@timers, stamp)
    @timers.pop(@timers.size - index)
  end

  # Return the left-most index where to insert item e, in a list a, assuming
  # a is sorted in descending order.
  def bisect_left(a, e, l = 0, u = a.length)
    while l < u
      m = l + (u - l).div(2)

      if a[m][:stamp] > e
        l = m + 1
      else
        u = m
      end
    end

    l
  end

  # Returns current time stamp based on CPU monotonic clock
  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
