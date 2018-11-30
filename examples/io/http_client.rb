# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def connect(host, port)
  proc do
    socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
    # socket = OpenSSL::SSL::SSLSocket.new(socket)
    Rubato::IO::SocketWrapper.new(socket, secure: true).tap do |o|
      await o.connect(host, port)
    end
  end
end

spawn do
  cancel_after(3) do
    io = Rubato::Net.tcp_connect('google.com', 443, secure: true)
    t0 = Time.now
    io.write("GET / HTTP/1.1\r\nHost: google.com\r\n\r\n")
    puts "write time: #{Time.now - t0}"
    t0 = Time.now
    reply = io.read(2**16)
    puts "read time: #{Time.now - t0}"
    puts
    puts reply
  end
rescue Rubato::Cancel
  puts "quitting due to inactivity"
end
