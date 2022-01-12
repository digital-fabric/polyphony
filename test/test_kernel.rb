# frozen_string_literal: true

require_relative 'helper'

class KernelTest < MiniTest::Test
  def test_system_method
    fn = '/tmp/test_system_method'
    FileUtils.rm(fn) rescue nil

    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    system('sleep 0.01')
    assert(counter >= 2)

    system('echo "hello" > ' + fn)
    assert_equal "hello\n", IO.read(fn)
  ensure
    timer&.stop
  end

  def test_Kernel_system_singleton_method
    assert_equal true, Kernel.system("which ruby > /dev/null 2>&1")
    assert_equal false, Kernel.system("azertyuiop > /dev/null 2>&1")
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

    `sleep 0.05`
    assert_in_range 6..20, counter

    result = `echo "hello"`
    assert_equal "hello\n", result
  ensure
    timer&.stop
  end
end
