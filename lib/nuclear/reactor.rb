# frozen_string_literal: true

export  :cancel_all_timers,
        :cancel_timer,
        :interval,
        :next_tick,
        :run,
        :timeout,
        :unwatch,
        :watch,
        :watched?

# Nuclear uses nio4r as sits selector/reactor engine
require 'nio'

Timers = import('./timers')

# Operations to perform on next loop iteration
NextTickOps = []

# Default selector
Selector = NIO::Selector.new(nil)

# Default timer group
TimerGroup = Timers::Group.new

# Registers an io instance with the default selector. The given block will be
# invoked once the given io is selected
# @param io [IO] io instance
# @param interests [:r, :rw, :w] read/write interests
# @return [void]
def watch(io, interests, &callback)
  Selector.register(io, interests).tap { |m| m.value = callback }
end

# Unregisters the given io instance with the default selector
# @return [void]
def unwatch(io)
  Selector.deregister(io)
end

def watched?(io)
  Selector.registered?(io)
end

def next_tick(&block)
  NextTickOps << block
end

# Runs the default selector loop
# @return [void]
def run
  trap('INT') { @run = false }

  @already_ran = true
  @run = true

  reactor_loop
  puts unless @run # play nice with shell, print a newline if interrupted
end

# Performs selector loop, monitoring ios and firing timers
# @return [void]
def reactor_loop
  while @run && should_run_reactor?
    NextTickOps.each(&:call)
    NextTickOps.clear

    interval = TimerGroup.idle_interval
    Selector.select(interval) { |m| m.value.(m) } unless Selector.empty?

    TimerGroup.fire unless interval.nil?
  end
end

# Returns true if any ios are monitored are any timers are pending
# @return [Boolean] should the default reactor loop
def should_run_reactor?
  !(Selector.empty? && TimerGroup.empty?)
end

# Adds a one-shot timer
# @param timeout [Float] timeout in seconds
# @return [Integer] timer id
def timeout(timeout, &callback)
  TimerGroup.timeout(timeout, &callback)
end

# Adds a recurring timer
# @param interval [Float] interval in seconds
# @param offset [Float] offset in seconds for first firing
# @return [Integer] timer id
def interval(interval, offset = nil, &callback)
  TimerGroup.interval(interval, offset, &callback)
end

# Cancels a pending timer
# @param id [Integer] timer id
# @return [void]
def cancel_timer(id)
  TimerGroup.cancel(id)
end

def cancel_all_timers
  TimerGroup.cancel_all
end

at_exit do
  run if !$! && !@already_ran && should_run_reactor?
end
