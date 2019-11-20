# frozen_string_literal: true

require_relative 'helper'

class SignalTest < MiniTest::Test
  def test_Gyro_Signal_constructor
    sig = Signal.list['USR1']
    count = 0
    w = Gyro::Signal.new(sig) do
      count += 1
      w.stop
    end
    Thread.new do
      sync_sleep 0.001
      Process.kill(:USR1, Process.pid)
    end
    suspend
    assert_equal(1, count)
  end

  def test_trap_api
    count = 0
    w = Polyphony.trap(:usr1, true) do
      count += 1
      w.stop
    end

    assert_kind_of(Gyro::Signal, w)
    Thread.new do
      sync_sleep 0.001
      Process.kill(:USR1, Process.pid)
    end
    suspend
    assert_equal(1, count)
  end
end
