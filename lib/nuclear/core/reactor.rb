# frozen_string_literal: true

export_default :Reactor

# Nuclear uses nio4r as sits selector/reactor engine
require 'nio'

Timers = import('./timers')

# Operations to perform on next loop iteration
NextTickOps = []

# Default selector
Selector = NIO::Selector.new(nil)

# Default timer group
TimerGroup = Timers::Group.new

# Reactor methods
module Reactor
  # Cancels all active timers
  # @return [void]
  def cancel_all_timers
    TimerGroup.cancel_all
  end

  # Cancels a pending timer
  # @param id [Integer] timer id
  # @return [void]
  def cancel_timer(id)
    TimerGroup.cancel(id)
  end

  # Adds a recurring timer
  # @param interval [Float] interval in seconds
  # @param offset [Float] offset in seconds for first firing
  # @return [Integer] timer id
  def interval(interval, offset = nil, &callback)
    TimerGroup.interval(interval, offset, &callback)
  end

  # Schedules an operation to be performed in the next reactor iteration
  # @return [void]
  def next_tick(&block)
    NextTickOps << block
  end

  # Runs the default selector loop
  # @return [void]
  def run_reactor
    trap('INT') { @reactor_running = false }

    @reactor_already_ran = true
    @reactor_running = true

    reactor_loop
    # play nice with shell, print a newline if interrupted
    puts unless @reactor_running
  end

  # Returns true if any ios are monitored are any timers are pending
  # @return [Boolean] should the default reactor loop
  def should_run_reactor?
    !(Selector.empty? && TimerGroup.empty? && NextTickOps.empty?)
  end

  # Adds a one-shot timer
  # @param timeout [Float] timeout in seconds
  # @return [Integer] timer id
  def timeout(timeout, &callback)
    TimerGroup.timeout(timeout, &callback)
  end

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

  # Returns true if the given io is currently watched
  # @param io [IO]
  # @return [Boolean]
  def watched?(io)
    Selector.registered?(io)
  end

  private

  # Performs selector loop, monitoring ios and firing timers
  # @return [void]
  def reactor_loop
    while @reactor_running && should_run_reactor?
      NextTickOps.slice!(0..-1).each(&:call) unless NextTickOps.empty?

      interval = TimerGroup.idle_interval
      Selector.select(interval) { |m| m.value.(m) } unless Selector.empty?

      TimerGroup.fire unless interval.nil?
    end
  end
end

extend Reactor

Kernel.at_exit do
  # Run reactor once all user files are loaded
  run_reactor if !$! && !@reactor_already_ran && should_run_reactor?
end
