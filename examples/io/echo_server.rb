# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  server = await Rubato::Net.tcp_listen(nil, 1234, reuse_addr: true, dont_linger: true)
  server.reuse_addr
  server.dont_linger
  puts "listening on port 1234..."

  loop do
    client = await server.accept
    spawn do
      move_on_after(3) do |scope|
        scope.when_cancelled do
          await client.write "Disconnecting due to inactivity\n"
        end
        loop do
          data = await client.read
          scope.reset_timeout
          await client.write(data)
        end  
      end
    rescue => e
      puts "client error: #{e.inspect}"
    ensure
      client.close
    end
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  server&.close
end
