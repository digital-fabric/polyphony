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

  def patch_open3
    class << Open3
      alias_method :orig_popen2, :popen2
      def popen2(*args)
        raise SystemCallError, 'foo'
      end
    end
  end

  def unpatch_open3
    class << Open3
      alias_method :popen2, :orig_popen2
    end
  end

  def test_system_method_with_system_call_error
    patch_open3
    result = system('foo')
    assert_nil result
  ensure
    unpatch_open3
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
