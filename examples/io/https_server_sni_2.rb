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

begin
  server.accept_loop(ignore_errors: false) do |socket|
    spin do
      while (data = socket.gets("\n", 8192))
        if data.chomp.empty?
          socket << "HTTP/1.1 200 OK\nConnection: close\nContent-Length: 4\n\nfoo\n"
          break
        end
      end
    rescue OpenSSL::SSL::SSLError
      # ignore
    end
  end
rescue => e
  puts '*' * 40
  p e
  puts e.backtrace.join("\n")
end
