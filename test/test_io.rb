require 'minitest/autorun'
require 'modulation'

module IOTests
  Core        = import('../lib/polyphony/core')
  import('../lib/polyphony/extensions/io')

  class IOTest < MiniTest::Test
    def setup
      EV.rerun
    end

    def test_that_io_does_not_block
      i, o = IO.pipe
      count = 0
      msg = nil
      [
        spawn {
          o.write("hello")
          o.close
        },

        spawn {
          while count < 5
            sleep 0.01
            count += 1
          end
        }, 

        spawn {
          msg = i.read
        }
      ].each(&:await)
      assert_equal(5, count)
      assert_equal("hello", msg)
    end
  end
end