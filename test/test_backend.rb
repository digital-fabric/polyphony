# frozen_string_literal: true

require_relative 'helper'

class BackendTest < MiniTest::Test
  def setup
    super
    @prev_backend = Thread.current.backend
    @backend = Polyphony::Backend.new
    Thread.current.backend = @backend
  end

  def teardown
    @backend.finalize
    Thread.current.backend = @prev_backend
  end

  def test_sleep
    count = 0
    t0 = Time.now
    spin {
      @backend.sleep 0.01
      count += 1
      @backend.sleep 0.01
      count += 1
      @backend.sleep 0.01
      count += 1
    }.await
    assert_in_delta 0.03, Time.now - t0, 0.005
    assert_equal 3, count
  end

  def test_write_read_partial
    i, o = IO.pipe
    buf = +''
    f = spin { @backend.read(i, buf, 5, false) }
    @backend.write(o, 'Hello world')
    return_value = f.await
    
    assert_equal 'Hello', buf
    assert_equal return_value, buf
  end

  def test_write_read_to_eof_limited_buffer
    i, o = IO.pipe
    buf = +''
    f = spin { @backend.read(i, buf, 5, true) }
    @backend.write(o, 'Hello')
    snooze
    @backend.write(o, ' world')
    snooze
    o.close
    return_value = f.await
    
    assert_equal 'Hello', buf
    assert_equal return_value, buf
  end

  def test_write_read_to_eof
    i, o = IO.pipe
    buf = +''
    f = spin { @backend.read(i, buf, 10**6, true) }
    @backend.write(o, 'Hello')
    snooze
    @backend.write(o, ' world')
    snooze
    o.close
    return_value = f.await
    
    assert_equal 'Hello world', buf
    assert_equal return_value, buf
  end

  def test_waitpid
    pid = fork do
      @backend.post_fork
      exit(42)
    end
    
    result = @backend.waitpid(pid)
    assert_equal [pid, 42], result
  end

  def test_read_loop
    i, o = IO.pipe

    buf = []
    f = spin do
      buf << :ready
      @backend.read_loop(i) { |d| buf << d }
      buf << :done
    end

    # writing always causes snoozing
    o << 'foo'
    o << 'bar'
    o.close

    f.await
    assert_equal [:ready, 'foo', 'bar', :done], buf
  end

  def test_accept_loop
    server = TCPServer.new('127.0.0.1', 1234)

    clients = []
    server_fiber = spin do
      @backend.accept_loop(server) { |c| clients << c }
    end

    c1 = TCPSocket.new('127.0.0.1', 1234)
    sleep 0.01

    assert_equal 1, clients.size

    c2 = TCPSocket.new('127.0.0.1', 1234)
    sleep 0.01

    assert_equal 2, clients.size

  ensure
    c1&.close
    c2&.close
    server_fiber.stop
    snooze
    server&.close
  end

  def test_timer_loop
    i = 0
    f = spin do
      @backend.timer_loop(0.01) { i += 1 }
    end
    @backend.sleep(0.05)
    f.stop
    f.await # TODO: check why this test sometimes segfaults if we don't a<wait fiber
    assert_in_range 4..6, i
  end

  class MyTimeoutException < Exception
  end

  def test_timeout
    buffer = []
    assert_raises(Polyphony::TimeoutException) do
      @backend.timeout(0.01, Polyphony::TimeoutException) do
        buffer << 1
        sleep 0.02
        buffer << 2
      end
    end
    assert_equal [1], buffer

    buffer = []
    assert_raises(MyTimeoutException) do
      @backend.timeout(0.01, MyTimeoutException) do
        buffer << 1
        sleep 1
        buffer << 2
      end
    end
    assert_equal [1], buffer

    buffer = []
    result = @backend.timeout(0.01, nil, 42) do
      buffer << 1
      sleep 1
      buffer << 2
    end
    assert_equal 42, result
    assert_equal [1], buffer
  end

  def test_nested_timeout
    buffer = []
    assert_raises(MyTimeoutException) do
      @backend.timeout(0.01, MyTimeoutException) do
        @backend.timeout(0.02, nil) do
          buffer << 1
          sleep 1
          buffer << 2
        end
      end
    end
    assert_equal [1], buffer
  end
end
