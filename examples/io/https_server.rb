# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'localhost/authority'

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}

server = Polyphony::Net.tcp_listen('localhost', 1234, opts)

puts 'Serving HTTPS on port 1234'

spin_loop(interval: 1) { STDOUT << '.' }

# server.accept_loop do |socket|
while (socket = server.accept)
  spin do
    while (data = socket.gets("\n", 8192))
      if data.chomp.empty?
        socket << "HTTP/1.1 200 OK\nConnection: close\nContent-Length: 4\n\nfoo\n"
        break
      end
    end
  end
end
