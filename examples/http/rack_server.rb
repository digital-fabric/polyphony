# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
app = Polyphony::HTTP::Rack.load(app_path)
opts = { reuse_addr: true, dont_linger: true }

puts 'listening on port 1234'
puts "pid: #{Process.pid}"
Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts, &app)
