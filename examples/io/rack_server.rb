# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')
Rack = import('../../lib/polyphony/http/rack')

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
rack = Rack.load(app_path)

spawn do
  opts = { reuse_addr: true, dont_linger: true }
  server = HTTPServer.serve('0.0.0.0', 1234, opts, &rack)
  puts "listening on port 1234"
  puts "pid: #{Process.pid}"
  server.await
end