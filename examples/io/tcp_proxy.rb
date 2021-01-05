# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

server1 = TCPServer.open('127.0.0.1', 1234)
server2 = TCPServer.open('127.0.0.1', 1235)

puts "Pid: #{Process.pid}"
puts 'Proxying port 1234 => port 1235'

client1 = client2 = nil

f1 = spin {
  client1 = server1.accept
  loop do
    if client2
      Thread.current.backend.splice_loop(client1, client2)
    end
  end
}

f2 = spin {
  client2 = server2.accept
  loop do
    if client1
      Thread.current.backend.splice_loop(client2, client1)
    end
  end
}

Fiber.await(f1, f2)
