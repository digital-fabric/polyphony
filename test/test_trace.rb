# frozen_string_literal: true

require_relative 'helper'
require 'polyphony/adapters/trace'

class TraceTest < MiniTest::Test
  def test_tracing_disabled
    records = []
    t = Polyphony::Trace.new { |r| records << r if r[:event] =~ /^fiber_/ }
    t.enable
    snooze
    assert_equal 0, records.size
  ensure
    t&.disable
    Polyphony.trace(nil)
  end

  def test_tracing_enabled
    records = []
    t = Polyphony::Trace.new(:fiber_all) { |r| records << r if r[:event] =~ /^fiber_/ }
    Polyphony.trace(true)
    t.enable
    snooze
    t.disable
    
    assert_equal 3, records.size
    events = records.map { |r| r[:event] }
    assert_equal [:fiber_schedule, :fiber_switchpoint, :fiber_run], events
    assert_equal [Fiber.current], records.map { |r| r[:fiber] }.uniq
  ensure
    t&.disable
    Polyphony.trace(nil)
  end

  def test_2_fiber_trace
    records = []
    thread = Thread.current
    t = Polyphony::Trace.new(:fiber_all) do |r|
      records << r if Thread.current == thread && r[:event] =~ /^fiber_/
    end
    t.enable
    Polyphony.trace(true)

    f = spin { sleep 0 }
    suspend
    sleep 0

    events = records.map { |r| [r[:fiber] == f ? :f : :current, r[:event]] }
    assert_equal [
      [:f, :fiber_create],
      [:f, :fiber_schedule],
      [:current, :fiber_switchpoint],
      [:f, :fiber_run],
      [:f, :fiber_switchpoint],
      [:f, :fiber_event_poll_enter],
      [:f, :fiber_schedule],
      [:f, :fiber_event_poll_leave],
      [:f, :fiber_run],
      [:f, :fiber_terminate],
      [:current, :fiber_switchpoint],
      [:current, :fiber_event_poll_enter],
      [:current, :fiber_schedule],
      [:current, :fiber_event_poll_leave],
      [:current, :fiber_run]
    ], events
  ensure
    t&.disable
    Polyphony.trace(nil)
  end
end
