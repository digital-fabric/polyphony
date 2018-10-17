# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def connect(host, port)
  addr = ::Socket.sockaddr_in(port, host)
  socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
  socket.connect addr
  Nuclear::IO::Wrapper.new(socket)
  # result = socket.connect_nonblock addr, exception: false
end


spawn do
  begin
    io = connect('google.com', 80)
    t0 = Time.now
    await io.write("GET / HTTP/1.1\r\nHost: google.com\r\n\r\n")
    puts "write time: #{Time.now - t0}"
    t0 = Time.now
    reply = await io.read(2**16)
    puts "read time: #{Time.now - t0}"
    puts
    puts reply
  rescue Cancelled
    puts "quitting due to inactivity"
  end
end
