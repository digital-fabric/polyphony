# frozen_string_literal: true

require_relative 'helper'

class SignalTest < MiniTest::Test
  def test_Gyro_Signal_constructor
    sig = Signal.list['USR1']
    count = 0
    w = Gyro::Signal.new(sig)

    spin {
      loop {
        w.await
        count += 1
        break
      }
    }
    Thread.new do
      orig_sleep 0.001
      Process.kill(:USR1, Process.pid)
    end
    suspend
    assert_equal 1, count
  end

  def test_wait_for_signal_api
    count = 0
    spin do
      Polyphony.wait_for_signal 'SIGHUP'
      count += 1
    end

    snooze
    Process.kill(:HUP, Process.pid)
    assert_equal 1, count
  end
end
