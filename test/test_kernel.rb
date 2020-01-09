# frozen_string_literal: true

require_relative 'helper'

class KernelTest < MiniTest::Test
  def test_system_method
    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    system('sleep 0.01')
    assert(counter >= 2)

    i, o = IO.pipe
    orig_stdout = $stdout
    $stdout = o
    system('echo "hello"')
    o.close
    assert_equal "hello\n", i.read
  ensure
    $stdout = orig_stdout
    timer&.stop
  end

  def test_backtick_method
    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    `sleep 0.01`
    assert(counter >= 2)

    result = `echo "hello"`
    assert_equal "hello\n", result
  ensure
    timer&.stop
  end
end
