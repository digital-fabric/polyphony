# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin_loop(interval: 5) { p Thread.backend.stats }

server = TCPServer.open('127.0.0.1', 1234)
puts "Pid: #{Process.pid}"
puts 'Echoing on port 1234...'
begin
  while (client = server.accept)
    spin do
      while (data = client.gets)
        # client.send("you said: #{data.chomp}!\n", 0)
        client.write('you said: ', data.chomp, "!\n")
      end
    rescue Errno::ECONNRESET
      'Connection reset...'
    ensure
      client.shutdown
      client.close
    end
  end
ensure
  server.close
end
