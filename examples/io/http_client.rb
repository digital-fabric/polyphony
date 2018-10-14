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
    Nuclear::Task.new do |t|
      read_from_io(t, max)
    end
  end

  def write(data)
    Nuclear::Task.new do |t|
      write_to_io(t, data)
    end
  end

  def connect(host, port)

  NO_EXCEPTION_OPTS = { exception: false }.freeze

  def read_from_io(task, max)
    result = @io.read_nonblock(max, NO_EXCEPTION_OPTS)
    case result
    when nil
      task.resolve RuntimeError.new('socket closed')
      close
    when :wait_readable
      fiber = Fiber.current
      create_read_watcher unless @read_watcher
      @read_watcher.start do
        @read_watcher.stop
        task.resolve @io.read_nonblock(max, NO_EXCEPTION_OPTS)
      end
      task.on_cancel { @read_watcher.stop }
    else
      task.resolve result
    end
  rescue => e
    puts "error: #{e}"
    puts e.backtrace.join("\n")
    task.resolve(e)
  end

  def write_to_io(task, data)
    result = @io.write_nonblock(data, exception: false)
    case result
    when nil
      task.resolve RuntimeError.new('socket closed')
      close
    when :wait_writable
      fiber = Fiber.current
      create_write_watcher unless @write_watcher
      @write_watcher.start do
        @write_watcher.stop
        write_to_io(task, data)
      end
      task.on_cancel { @write_watcher.stop }
    else
      if result == data.bytesize
        task.resolve(result)
      else
        write_to_io(data.slice(0, result))
      end
    end
  rescue => e
    task.resolve(e)
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


async! do
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
