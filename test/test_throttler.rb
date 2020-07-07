# frozen_string_literal: true

require_relative 'helper'

class ThrottlerTest < MiniTest::Test
  def test_throttler_with_rate
    t = Polyphony::Throttler.new(50)
    buffer = []
    f = spin { loop { t.process { buffer << 1 } } }
    sleep 0.2
    f.stop
    snooze
    assert buffer.size >= 8
    assert buffer.size <= 12
  ensure
    t.stop
  end

  def test_throttler_with_hash_of_rate
    t = Polyphony::Throttler.new(rate: 20)
    buffer = []
    f = spin do
      loop { t.process { buffer << 1 } }
    end
    sleep 0.25
    f.stop
    assert (2..6).include?(buffer.size)
  ensure
    t.stop
  end

  def test_throttler_with_hash_of_interval
    t = Polyphony::Throttler.new(interval: 0.01)
    buffer = []
    f = spin { loop { t.process { buffer << 1 } } }
    sleep 0.02
    f.stop
    assert buffer.size >= 2
    assert buffer.size <= 3
  ensure
    t.stop
  end

  def test_throttler_with_invalid_argument
    assert_raises RuntimeError do
      Polyphony::Throttler.new(:foobar)
    end
  end
end