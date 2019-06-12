# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

opts = {
  reuse_addr: true,
  dont_linger: true
}

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
    # req.send_headers
    # req.send_body_chunk("Method: #{req.method}\n")
    # req.send_body_chunk("Path: #{req.path}\n")
    # req.send_body_chunk("Query: #{req.query.inspect}\n", done: true)
  end
rescue Exception => e
  puts "*" * 40
  p e
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."