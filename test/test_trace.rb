# frozen_string_literal: true

require_relative 'helper'

class TraceTest < MiniTest::Test
  def test_tracing_enabled
    events = []
    Thread.backend.trace_proc = proc { |*e| events << e }
    snooze
    
    assert_equal [
      [:fiber_schedule, Fiber.current, nil, 0],
      [:fiber_switchpoint, Fiber.current],
      [:fiber_run, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_2_fiber_trace
    events = []
    Thread.backend.trace_proc = proc { |*e| events << e }

    f = spin { sleep 0; :byebye }
    suspend
    sleep 0

    assert_equal [
      [:fiber_create, f],
      [:fiber_schedule, f, nil, 0],
      [:fiber_switchpoint, Fiber.current],
      [:fiber_run, f, nil],
      [:fiber_switchpoint, f],
      [:fiber_event_poll_enter, f],
      [:fiber_schedule, f, nil, 0],
      [:fiber_event_poll_leave, f],
      [:fiber_run, f, nil],
      [:fiber_terminate, f, :byebye],
      [:fiber_switchpoint, f],
      [:fiber_switchpoint, Fiber.current],
      [:fiber_event_poll_enter, Fiber.current],
      [:fiber_schedule, Fiber.current, nil, 0],
      [:fiber_event_poll_leave, Fiber.current],
      [:fiber_run, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end
end
