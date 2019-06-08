# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

server = TCPServer.open(1234)
puts "Echoing on port 1234..."
while client = server.accept
  spin do
    while data = client.readpartial(8192) rescue nil
      client.write("you said: ", data.chomp, "!\n")
    end
  end
end
