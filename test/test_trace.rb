# frozen_string_literal: true

require_relative 'helper'

class TraceTest < MiniTest::Test
  def test_tracing_disabled
    records = []
    t = Polyphony::Trace.new { |r| records << r if r[:event] =~ /^fiber_/ }
    t.enable
    snooze
    assert_equal 0, records.size
  ensure
    t.disable
    Gyro.trace(nil)
  end

  def test_tracing_enabled
    records = []
    t = Polyphony::Trace.new { |r| records << r if r[:event] =~ /^fiber_/ }
    t.enable
    Gyro.trace(true)
    snooze
    t.disable
    
    assert_equal 3, records.size
    events = records.map { |r| r[:event] }
    assert_equal [:fiber_schedule, :fiber_switchpoint, :fiber_run], events
    assert_equal [Fiber.current], records.map { |r| r[:fiber] }.uniq
  ensure
    t.disable
    Gyro.trace(nil)
  end

  def test_2_fiber_trace
    records = []
    t = Polyphony::Trace.new { |r| records << r if r[:event] =~ /^fiber_/ }
    t.enable
    Gyro.trace(true)

    f = spin { sleep 0 }
    suspend
    sleep 0

    events = records.map { |r| [r[:fiber], r[:event]] }
    assert_equal [
      [f, :fiber_create],
      [f, :fiber_schedule],
      [Fiber.current, :fiber_switchpoint],
      [f, :fiber_run],
      [f, :fiber_switchpoint],
      [f, :fiber_ev_loop_enter],
      [f, :fiber_schedule],
      [f, :fiber_ev_loop_leave],
      [f, :fiber_run],
      [f, :fiber_terminate],
      [Fiber.current, :fiber_switchpoint],
      [Fiber.current, :fiber_ev_loop_enter],
      [Fiber.current, :fiber_schedule],
      [Fiber.current, :fiber_ev_loop_leave],
      [Fiber.current, :fiber_run]
    ], events
  ensure
    t.disable
    Gyro.trace(nil)
  end
end
