# frozen_string_literal: true

export  :timeout,
        :interval,
        :cancel_timer,
        :watch,
        :unwatch,
        :selectable_count,
        :loop,
        :reset!

require 'nio'

Timers = import('./timers')

def watch(io, interests, &block)
  Selector.register(io, interests).tap { |m| m.value = block }
end

def unwatch(io)
  Selector.deregister(io)
end

def selectable_count
  Selector.selectables&.size
end

module ::NIO
  # Extensions for NIO::Selector
  class Selector
    attr_reader :selectables
  end
end

Selector = NIO::Selector.new(nil)
TimerGroup = Timers::Group.new

def reset!
  orig_verbose = $VERBOSE
  $VERBOSE = nil  
  const_set(:Selector, NIO::Selector.new(nil))
  const_set(:TimerGroup, Timers::Group.new)
ensure
  $VERBOSE = orig_verbose
end

def loop
  @already_ran = true
  @run = true
  trap('INT') { @run = false }
  loop_run
  puts unless @run # play nice with shell
end

def loop_run
  while @run && should_run_event_loop?
    interval = TimerGroup.idle_interval
    Selector.select(interval) { |m| m.value.(m) }
    TimerGroup.fire unless interval.nil?
  end
end

def should_run_event_loop?
  !(Selector.empty? && TimerGroup.empty?)
end

def timeout(duration, &block)
  TimerGroup.timeout(duration, &block)
end

def interval(duration, &block)
  TimerGroup.interval(duration, &block)
end

def cancel_timer(id)
  TimerGroup.cancel(id)
end

at_exit do
  loop if !$! && !@already_ran && should_run_event_loop?
end
