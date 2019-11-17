# frozen_string_literal: true

require_relative 'helper'

class SignalTest < MiniTest::Test
  def test_Gyro_Signal_constructor
    sig = Signal.list['USR1']
    count = 0
    w = Gyro::Signal.new(sig) { count += 1; w.stop }
    Thread.new { sync_sleep 0.001; Process.kill(:USR1, Process.pid) }
    suspend
    assert_equal(1, count)
  end

  def test_trap_api
    count = 0
    w = Polyphony.trap(:usr1, true) { count += 1; w.stop }
    assert_kind_of(Gyro::Signal, w)
    Thread.new { sync_sleep 0.001; Process.kill(:USR1, Process.pid) }
    suspend
    assert_equal(1, count)
  end
end
