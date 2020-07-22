# frozen_string_literal: true

require_relative 'helper'

class EventTest < MiniTest::Test
  def test_that_event_receives_signal_across_threads
    count = 0
    a = Polyphony::Event.new
    spin {
      a.await
      count += 1
    }
    snooze
    t = Thread.new do
      orig_sleep 0.001
      a.signal
    end
    suspend
    assert_equal 1, count
  ensure
    t&.kill
    t&.join
  end

  def test_that_event_coalesces_signals
    count = 0
    a = Polyphony::Event.new
   
    coproc = spin {
      loop {
        a.await
        count += 1
        spin { coproc.stop }
      }
    }
    snooze

    t = Thread.new do
      orig_sleep 0.001
      3.times { a.signal }
    end

    coproc.await
    assert_equal 1, count
  ensure
    t&.kill
    t&.join
  end

  def test_exception_while_waiting_for_event
    e = Polyphony::Event.new

    f = spin { e.await }
    g = spin { f.raise 'foo' }

    assert_raises(RuntimeError) do
      f.await
    end
  end
end
