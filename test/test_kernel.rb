# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler/setup'
require 'polyphony'

class KernelTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_system_method
    counter = 0
    timer = coproc {
      throttled_loop(200) { counter += 1 }
    }

    system('sleep 0.01')
    assert(counter >= 2)

    result = system('echo "hello"')
    assert_equal("hello\n", result)
  ensure
    timer&.stop
  end
end