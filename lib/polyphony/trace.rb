# frozen_string_literal: true

export :new, :analyze

require 'polyphony'

STOCK_EVENTS = %i[line call return c_call c_return b_call b_return].freeze

def new(*events)
  start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  events = STOCK_EVENTS if events.empty?
  ::TracePoint.new(*events) { |tp| yield trace_record(tp, start_stamp) }
end

def trace_record(trp, start_stamp)
  stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_stamp
  { stamp: stamp, self: trp.self, binding: trp.binding, event: trp.event,
    fiber: tp_fiber(trp), lineno: trp.lineno, method_id: trp.method_id,
    file: trp.path, parameters: tp_params(trp),
    return_value: tp_return_value(trp), schedule_value: tp_schedule_value(trp),
    exception: tp_raised_exception(trp) }
end

def tp_fiber(trp)
  trp.is_a?(FiberTracePoint) ? trp.fiber : Fiber.current
end

PARAMS_EVENTS = %i[call c_call b_call].freeze

def tp_params(trp)
  PARAMS_EVENTS.include?(trp.event) ? trp.parameters : nil
end

RETURN_VALUE_EVENTS = %i[return c_return b_return].freeze

def tp_return_value(trp)
  RETURN_VALUE_EVENTS.include?(trp.event) ? trp.return_value : nil
end

SCHEDULE_VALUE_EVENTS = %i[fiber_schedule fiber_run].freeze

def tp_schedule_value(trp)
  SCHEDULE_VALUE_EVENTS.include?(trp.event) ? trp.value : nil
end

def tp_raised_exception(trp)
  trp.event == :raise && trp.raised_exception
end

def analyze(records)
  by_fiber = Hash.new { |h, f| h[f] = [] }
  records.each_with_object(by_fiber) { |r, h| h[r[:fiber]] << r }
  { by_fiber: by_fiber }
end

# Implements fake TracePoint instances for fiber-related events
class FiberTracePoint
  attr_reader :event, :fiber, :value

  def initialize(tpoint)
    @tp = tpoint
    @event = tpoint.return_value[0]
    @fiber = tpoint.return_value[1]
    @value = tpoint.return_value[2]
  end

  def lineno
    @tp.lineno
  end

  def method_id
    @tp.method_id
  end

  def path
    @tp.path
  end

  def self
    @tp.self
  end

  def binding
    @tp.binding
  end
end

class << ::TracePoint
  alias_method :orig_new, :new
  def new(*args, &block)
    polyphony_file_regexp = /^#{::Exception::POLYPHONY_DIR}/

    events_mask, fiber_events_mask = event_masks(args)

    orig_new(*events_mask) do |tp|
      # next unless !$watched_fiber || Fiber.current == $watched_fiber

      if tp.method_id == :__fiber_trace__
        next if tp.event != :c_return
        next unless fiber_events_mask.include?(tp.return_value[0])
        
        block.(FiberTracePoint.new(tp))
      else
        next if tp.path =~ polyphony_file_regexp

        block.(tp)
      end
    end
  end

  ALL_FIBER_EVENTS = %i[
    fiber_create fiber_terminate fiber_schedule fiber_switchpoint fiber_run
    fiber_ev_loop_enter fiber_ev_loop_leave
  ]

  def event_masks(events)
    events.inject([[], []]) do |masks, e|
      case e
      when :fiber_all
        masks[1] += ALL_FIBER_EVENTS
        masks[0] << :c_return unless masks[0].include?(:c_return)
      when /fiber_/
        masks[1] << e
        masks[0] << :c_return unless masks[0].include?(:c_return)
      else
        masks[0] << e
      end
      masks
    end
  end
end
