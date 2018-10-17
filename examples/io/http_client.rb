# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

class IOWrapper
  def initialize(io)
    @io = io
  end

  def close
    @read_watcher&.stop
    @write_watcher&.stop
    @io.close
  end

  def read(max = 8192)
    proc do
      read_from_io(Fiber.current, max)
    end
  end

  def write(data)
    proc do
      write_to_io(Fiber.current, data)
    end
  end

  NO_EXCEPTION_OPTS = { exception: false }.freeze

  def read_from_io(fiber, max)
    result = @io.read_nonblock(max, NO_EXCEPTION_OPTS)
    case result
    when nil
      close
      raise RuntimeError.new('socket closed')
    when :wait_readable
      create_read_watcher unless @read_watcher
      @read_watcher.start do
        @read_watcher.stop
        fiber.resume @io.read_nonblock(max, NO_EXCEPTION_OPTS)
      end
      suspend
    else
      result
    end
  ensure
    @read_watcher&.stop
  end

  def write_to_io(fiber, data)
    paused = true
    loop do
      result = @io.write_nonblock(data, exception: false)
      case result
      when nil
        close
        raise RuntimeError.new('socket closed')
      when :wait_writable
        create_write_watcher unless @write_watcher
        @write_watcher.start do
          @write_watcher.stop
          fiber.resume
        end
        paused = true
        suspend
      else
        if result == data.bytesize
          return result
        else
          data = data[result..-1]
        end
      end
    end
  ensure
    @write_watcher&.stop
  end

  def create_read_watcher
    @read_watcher = EV::IO.new(@io, :r, false) {}
  end

  def create_write_watcher
    @read_watcher = EV::IO.new(@io, :w, false) {}
  end
end

def connect(host, port)
  addr = ::Socket.sockaddr_in(port, host)
  socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
  socket.connect addr
  IOWrapper.new(socket)
  # result = socket.connect_nonblock addr, exception: false
end


spawn do
  begin
    io = connect('google.com', 80)
    await io.write("GET / HTTP/1.1\r\n\r\n")
    t0 = Time.now
    reply = await io.read(2**16)
    puts "elapsed: #{Time.now - t0}"
    puts reply
  rescue Cancelled
    puts "quitting due to inactivity"
  end
end
