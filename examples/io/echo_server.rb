# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  socket = ::Socket.new(:INET, :STREAM)
  server = Nuclear::IO::SocketWrapper.new(socket)
  await server.bind('127.0.0.1', 1234)
  await server.listen
  puts "listening on port 1234..."

  loop do
    client = await server.accept
    puts "accept #{client.inspect}"
    spawn do
      move_on_after(60) do |scope|
        loop do
          await client.write("Say something...\n")
          data = await client.read
          scope.reset_timeout
          await client.write("You said: #{data}")
        end
        puts "moved on due to inactivity"
      end
    rescue => e
      puts "client error: #{e.inspect}"
    ensure
      client.close
    end
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  server.close
end
