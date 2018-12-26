# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')
Rack = import('../../lib/rubato/http/rack')

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
rack = Rack.load(app_path)

spawn do
  authority = Localhost::Authority.fetch
  opts = {
    reuse_addr: true,
    dont_linger: true,
    secure_context: authority.server_context
  }
  server = HTTPServer.serve('0.0.0.0', 1234, opts, &rack)
  puts "listening on port 1234"
  puts "pid: #{Process.pid}"
  server.await
end
