# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'localhost/authority'

authority = Localhost::Authority.fetch
server_ctx = authority.server_context

resolver = spin_loop do
  name, client = receive
  client << server_ctx
end

server_ctx.servername_cb = proc do |_socket, name|
  resolver << [name, Fiber.current]
  receive
end

opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: server_ctx
}

server = Polyphony::Net.tcp_listen('localhost', 1234, opts)

puts 'Serving HTTPS on port 1234'

# server.accept_loop do |socket|
server.accept_loop do |socket|
# while (socket = (server.accept)
  spin do
    while (data = socket.gets("\n", 8192))
      if data.chomp.empty?
        socket << "HTTP/1.1 200 OK\nConnection: close\nContent-Length: 4\n\nfoo\n"
        break
      end
    end
  end
end
