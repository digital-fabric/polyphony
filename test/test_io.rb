require 'minitest/autorun'
require 'bundler/setup'
require 'polyphony'

class IOTest < MiniTest::Test
  def setup
    EV.rerun
    @i, @o = IO.pipe
  end

  def test_that_io_op_yields_to_other_fibers
    count = 0
    msg = nil
    [
      spawn {
        @o.write("hello")
        @o.close
      },

      spawn {
        while count < 5
          sleep 0.01
          count += 1
        end
      }, 

      spawn {
        msg = @i.read
      }
    ].each(&:await)
    assert_equal(5, count)
    assert_equal("hello", msg)
  end

  def test_that_double_chevron_method_returns_io
    assert_equal(@o, @o << 'foo')

    @o << 'bar' << 'baz'
    @o.close
    assert_equal('foobarbaz', @i.read)
  end
end