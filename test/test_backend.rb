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

  def test_read_loop_terminate
    i, o = IO.pipe

    buf = []
    parent = spin do
      f = spin do
        buf << :ready
        @backend.read_loop(i) { |d| buf << d }
        buf << :done
      end
      suspend
    end

    # writing always causes snoozing
    o << 'foo'
    sleep 0.01
    o << 'bar'
    sleep 0.01

    parent.stop

    parent.await
    assert_equal [:ready, 'foo', 'bar'], buf
  end

  Net = Polyphony::Net

  def test_accept
    server = Net.listening_socket_from_options('127.0.0.1', 1234, reuse_addr: true)

    clients = []
    server_fiber = spin_loop do
      c = @backend.accept(server, TCPSocket)
      clients << c
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
    server_fiber&.stop
    snooze
    server&.close
  end

  def test_accept_loop
    server = Net.listening_socket_from_options('127.0.0.1', 1235, reuse_addr: true)

    clients = []
    server_fiber = spin do
      @backend.accept_loop(server, TCPSocket) { |c| clients << c }
    end

    c1 = TCPSocket.new('127.0.0.1', 1235)
    sleep 0.01

    assert_equal 1, clients.size

    c2 = TCPSocket.new('127.0.0.1', 1235)
    sleep 0.01

    assert_equal 2, clients.size
  ensure
    c1&.close
    c2&.close
    server_fiber&.stop
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

  def test_splice
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil

    spin {
      len = o2.splice(i1, 1000)
      o2.close
    }

    o1.write('foobar')
    result = i2.read

    assert_equal 'foobar', result
    assert_equal 6, len
  end

  def test_splice_to_eof
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil

    f = spin {
      len = o2.splice_to_eof(i1, 1000)
      o2.close
    }

    o1.write('foo')
    result = i2.readpartial(1000)
    assert_equal 'foo', result

    o1.write('bar')
    result = i2.readpartial(1000)
    assert_equal 'bar', result
    o1.close
    f.await
    assert_equal 6, len
  ensure
    if f.alive?
      f.interrupt
      f.await
    end
  end
end

class BackendChainTest < MiniTest::Test
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

  def test_simple_write_chain
    skip

    i, o = IO.pipe

    result = Thread.backend.chain(
      [:write, o, 'hello'],
      [:write, o, ' world']
    )

    assert_equal 6, result
    o.close
    assert_equal 'hello world', i.read
  end

  def chunk_header(len)
    "Content-Length: #{len}\r\n\r\n"
  end

  def serve_io(from, to)
    i, o = IO.pipe
    backend = Thread.current.backend
    while true
      len = o.splice(from, 8192)
      break if len == 0
      
      backend.chain(
        [:write, to, chunk_header(len)],
        [:splice, i, to, len]
      )
    end
    to.close
  end

  def test_chain_with_splice
    skip

    from_r, from_w = IO.pipe
    to_r, to_w = IO.pipe

    result = nil
    f = spin { serve_io(from_r, to_w) }

    from_w << 'Hello world!'
    from_w.close

    assert_equal "Content-Length: 12\r\n\r\nHello world!", to_r.read
  end

  def test_invalid_op
    skip

    i, o = IO.pipe

    assert_raises(RuntimeError) {
      Thread.backend.chain(
        [:read, o]
      )
    }

    assert_raises(RuntimeError) {
      Thread.backend.chain(
        [:write, o]
      )
    }
  end
end
