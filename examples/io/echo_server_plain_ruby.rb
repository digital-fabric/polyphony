# frozen_string_literal: true

require 'socket'

puts "Pid: #{Process.pid}"
server = TCPServer.open('127.0.0.1', 1234)
puts 'Echoing on port 1234...'
begin
  while (client = server.accept)
    Thread.new do
      while (data = client.gets)
        # client.send("you said: #{data.chomp}!\n", 0)
        client.write('you said: ', data.chomp, "!\n")
      end
    rescue Errno::ECONNRESET
      'Connection reset...'
    ensure
      puts "Closing client socket"
      client.shutdown
      client.close
    end
  end
ensure
  puts "Closing server"
  server.close
end
