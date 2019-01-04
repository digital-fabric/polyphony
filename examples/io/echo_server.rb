# frozen_string_literal: true

require 'modulation'
Polyphony = import('../../lib/polyphony')

server = TCPServer.open(1234)
puts "Echoing on port 1234..."
while client = server.accept
  spawn do
    while data = client.read rescue nil
      client.write(data)
    end
  end
end
