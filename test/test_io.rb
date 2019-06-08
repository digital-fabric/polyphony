# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler/setup'
require 'polyphony'
require 'fileutils'

class IOTest < MiniTest::Test
  def setup
    EV.rerun
    @i, @o = IO.pipe
  end

  def test_that_io_op_yields_to_other_fibers
    count = 0
    msg = nil
    [
      spin {
        @o.write("hello")
        @o.close
      },

      spin {
        while count < 5
          sleep 0.01
          count += 1
        end
      }, 

      spin {
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

class IOClassMethodsTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_binread
    s = IO.binread(__FILE__)
    assert_kind_of(String, s)
    assert(!s.empty?)
    assert_equal(IO.orig_binread(__FILE__), s)

    s = IO.binread(__FILE__, 100)
    assert_equal(100, s.bytesize)
    assert_equal(IO.orig_binread(__FILE__, 100), s)

    s = IO.binread(__FILE__, 100, 2)
    assert_equal(100, s.bytesize)
    assert_equal('frozen', s[0..5])
  end

  BIN_DATA = "\x00\x01\x02\x03"

  def test_binwrite
    fn = '/tmp/test_binwrite'
    FileUtils.rm(fn) rescue nil

    len = IO.binwrite(fn, BIN_DATA)
    assert_equal(4, len)
    s = IO.binread(fn)
    assert_equal(BIN_DATA, s)
  end

  def test_foreach
    lines = []
    IO.foreach(__FILE__) { |l| lines << l }
    assert_equal("# frozen_string_literal: true\n", lines[0])
    assert_equal("end", lines[-1])
  end

  def test_read
    s = IO.read(__FILE__)
    assert_kind_of(String, s)
    assert(!s.empty?)
    assert_equal(IO.orig_read(__FILE__), s)

    s = IO.read(__FILE__, 100)
    assert_equal(100, s.bytesize)
    assert_equal(IO.orig_read(__FILE__, 100), s)

    s = IO.read(__FILE__, 100, 2)
    assert_equal(100, s.bytesize)
    assert_equal('frozen', s[0..5])
  end

  def test_readlines
    lines = IO.readlines(__FILE__)
    assert_equal("# frozen_string_literal: true\n", lines[0])
    assert_equal("end", lines[-1])
  end

  WRITE_DATA = "foo\nbar קוקו"

  def test_write
    fn = '/tmp/test_write'
    FileUtils.rm(fn) rescue nil

    len = IO.write(fn, WRITE_DATA)
    assert_equal(WRITE_DATA.bytesize, len)
    s = IO.read(fn)
    assert_equal(WRITE_DATA, s)
  end

  def test_popen
    counter = 0
    timer = spin {
      throttled_loop(200) { counter += 1 }
    }

    IO.popen('sleep 0.01') { |io| io.read }
    assert(counter >= 2)

    result = nil
    IO.popen('echo "foo"') { |io| result = io.read }
    assert_equal("foo\n", result)
  ensure
    timer&.stop
  end
end