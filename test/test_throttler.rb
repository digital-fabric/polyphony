# frozen_string_literal: true

require_relative 'helper'

class ThrottlerTest < MiniTest::Test
  def test_throttler_with_rate
    t = Polyphony::Throttler.new(100)
    buffer = []
    f = spin { loop { t.process { buffer << 1 } } }
    sleep 0.02
    f.stop
    assert buffer.size >= 2
    assert buffer.size <= 3
  end

  def test_throttler_with_hash_of_rate
    t = Polyphony::Throttler.new(rate: 100)
    buffer = []
    f = spin { loop { t.process { buffer << 1 } } }
    sleep 0.02
    f.stop
    assert buffer.size >= 2
    assert buffer.size <= 3
  end

  def test_throttler_with_hash_of_interval
    t = Polyphony::Throttler.new(interval: 0.01)
    buffer = []
    f = spin { loop { t.process { buffer << 1 } } }
    sleep 0.02
    f.stop
    assert buffer.size >= 2
    assert buffer.size <= 3
  end
end