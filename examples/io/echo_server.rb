# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

server = TCPServer.open('127.0.0.1', 1234)
puts 'Echoing on port 1234...'
while (client = server.accept)
  spin do
    while (data = client.gets)
      client.write('you said: ', data.chomp, "!\n")
    end
  rescue Errno::ECONNRESET
    'Connection reset...'
  end
end
