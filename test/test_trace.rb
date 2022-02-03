# frozen_string_literal: true

require_relative 'helper'

class TraceTest < MiniTest::Test
  def test_tracing_enabled
    events = []
    Thread.backend.trace_proc = proc { |*e| events << e }
    snooze

    assert_equal [
      [:fiber_schedule, Fiber.current, nil, false],
      [:fiber_switchpoint, Fiber.current, ["#{__FILE__}:#{__LINE__ - 4}:in `test_tracing_enabled'"] + caller],
      [:fiber_run, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_2_fiber_trace
    events = []
    Thread.backend.trace_proc = proc { |*e| events << e }

    f = spin { sleep 0; :byebye }
    l0 = __LINE__ + 1
    suspend
    sleep 0

    Thread.backend.trace_proc = nil
    
    # remove caller info for :fiber_switchpoint events
    events.each {|e| e.pop if e[0] == :fiber_switchpoint }

    assert_equal [
      [:fiber_create, f],
      [:fiber_schedule, f, nil, false],
      [:fiber_switchpoint, Fiber.current],
      [:fiber_run, f, nil],
      [:fiber_switchpoint, f],
      [:fiber_event_poll_enter, f],
      [:fiber_schedule, f, nil, false],
      [:fiber_event_poll_leave, f],
      [:fiber_run, f, nil],
      [:fiber_terminate, f, :byebye],
      [:fiber_switchpoint, f],
      [:fiber_switchpoint, Fiber.current],
      [:fiber_event_poll_enter, Fiber.current],
      [:fiber_schedule, Fiber.current, nil, false],
      [:fiber_event_poll_leave, Fiber.current],
      [:fiber_run, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end
end
