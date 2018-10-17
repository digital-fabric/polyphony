# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def connect(host, port)
  proc do
    socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
    # socket = OpenSSL::SSL::SSLSocket.new(socket)
    Nuclear::IO::SocketWrapper.new(socket, secure: true).tap do |o|
      await o.connect(host, port)
    end
  end
end


spawn do
  io = await connect('google.com', 443)
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
