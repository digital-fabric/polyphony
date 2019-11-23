# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

begin
  server = Polyphony::Net.tcp_listen(
    nil, 1234, reuse_addr: true, dont_linger: true
  )
  puts 'listening on port 1234...'

  loop do
    client = server.accept
    client.write "Hi there\n"
    spin do
      cancel_scope = nil
      move_on_after(5) do |scope|
        scope.when_cancelled do
          client.write "Disconnecting due to inactivity\n"
        end
        while (data = client.readpartial(8192))
          scope.reset_timeout
          client.write "You said: #{data}"
        end
      end
    rescue StandardError => e
      puts "client error: #{e.inspect}"
    ensure
      client.close
    end
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  server&.close
end
