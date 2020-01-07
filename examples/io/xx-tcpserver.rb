# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

server = TCPServer.new('127.0.0.1', 1234)

puts 'echoing on port 1234'
while (socket = server.accept)
  spin do
    while (data = socket.gets(8192))
      socket << "you said: #{data}"
    end
  end
end
