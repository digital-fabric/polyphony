# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

begin
  server = Polyphony::Net.tcp_listen(nil, 1234, reuse_addr: true, dont_linger: true)
  puts "listening on port 1234..."

  loop do
    client = server.accept
    coproc do
      cancel_scope = nil
      move_on_after(5) do |s|
        cancel_scope = s
        while (data = client.readpartial(8192))
          s.reset_timeout
          client.write(data)
        end
      end
      client.write "Disconnecting due to inactivity\n" if cancel_scope.cancelled?
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
