# frozen_string_literal: true

require_relative 'helper'

class ExceptionTest < MiniTest::Test
  def test_sanitize
    prev_disable = Exception.__disable_sanitized_backtrace__
    Exception.__disable_sanitized_backtrace__ = false

    begin
      lineno = __LINE__ + 1
      spin { raise 'foo' }
      suspend
    rescue => e
    end

    assert_kind_of Exception, e
    backtrace = e.backtrace
    location = "#{__FILE__}:#{lineno}"
    assert_match /#{location}/, backtrace[0]
    polyphony_re = /^#{Exception::POLYPHONY_DIR}/
    assert_equal [], backtrace.select { |l| l =~ polyphony_re }

    Exception.__disable_sanitized_backtrace__ = true
    begin
      lineno = __LINE__ + 1
      spin { raise 'foo' }
      suspend
    rescue => e
    end

    assert_kind_of Exception, e
    backtrace = e.backtrace
    location = "#{__FILE__}:#{lineno}"
    assert_match /#{location}/, backtrace[0]
    assert_match /lib\/polyphony\/extensions\/fiber.rb/, backtrace[1]
    assert_match /lib\/polyphony\/extensions\/fiber.rb/, backtrace[2]
  ensure
    Exception.__disable_sanitized_backtrace__ = prev_disable
  end

end

class ProcessTest < MiniTest::Test
  def test_process_detach
    pid = Polyphony.fork { sleep 0.05; exit! 42 }
    buffer = []
    spin { 3.times { |i| buffer << i; snooze } }
    w = Process.detach(pid)

    assert_kind_of Fiber, w
    result = w.await

    assert_equal [0, 1, 2], buffer
    assert_equal [pid, 42], result
  end
end

class KernelTest < MiniTest::Test
  def test_backticks
    buffer = []
    spin { 3.times { |i| buffer << i; snooze } }
    data = `sleep 0.01; echo hello`

    assert_equal [0, 1, 2], buffer
    assert_equal "hello\n", data
  end

  def test_backticks_stderr
    prev_stderr = $stderr
    $stderr = err_io = StringIO.new

    data = `>&2 echo "error"`
    $stderr.rewind
    $stderr = prev_stderr

    assert_equal '', data
    assert_equal "error\n", err_io.read
  ensure
    $stderr = prev_stderr
  end

  def test_gets
    prev_stdin = $stdin
    i, o = IO.pipe
    $stdin = i

    spin { o << "hello\n" }
    s = gets

    assert_equal "hello\n", s
  ensure
    $stdin = prev_stdin
  end

  def test_multiline_gets
    prev_stdin = $stdin
    i, o = IO.pipe
    $stdin = i

    spin do
      o << "hello\n"
      o << "world\n"
      o << "nice\n"
      o << "to\n"
      o << "meet\n"
      o << "you\n"
    end

    s = +''
    6.times { s << gets }

    assert_equal "hello\nworld\nnice\nto\nmeet\nyou\n", s
  ensure
    $stdin = prev_stdin
  end

  def test_gets_from_argv
    prev_stdin = $stdin

    ARGV << __FILE__
    ARGV << __FILE__

    contents = IO.read(__FILE__).lines
    count = contents.size

    buffer = []
    (count * 2).times { |i| s = gets; buffer << s }
    assert_equal contents * 2, buffer

    i, o = IO.pipe
    $stdin = i

    spin { o << "hello\n" }
    s = gets

    assert_equal "hello\n", s
  ensure
    $stdin = prev_stdin
  end

  def test_gets_from_bad_argv
    prev_stdin = $stdin

    ARGV << 'foobar'

    begin
      gets
    rescue => e
    end

    assert_kind_of Errno::ENOENT, e
  ensure
    $stdin = prev_stdin
  end

  def test_system
    prev_stdout = $stdout
    $stdout = out_io = StringIO.new

    buffer = []
    spin { 3.times { |i| buffer << i; snooze } }
    system('sleep 0.01; echo hello')
    out_io.rewind
    $stdout = prev_stdout

    assert_equal [0, 1, 2], buffer
    assert_equal "hello\n", out_io.read
  ensure
    $stdout = prev_stdout
  end
end

class TimeoutTest < MiniTest::Test
  def test_that_timeout_yields_to_other_fibers
    buffer = []
    spin { 3.times { |i| buffer << i; snooze } }
    assert_raises(Timeout::Error) { Timeout.timeout(0.05) { sleep 1 } }
    assert_equal [0, 1, 2], buffer
  end

  class MyTimeout < Exception
  end

  def test_that_timeout_method_accepts_custom_error_class_and_message
    e = nil
    begin
      Timeout.timeout(0.05, MyTimeout, 'foo') { sleep 1 }
    rescue Exception => e
    end

    assert_kind_of MyTimeout, e
    assert_equal 'foo', e.message
  end
end
