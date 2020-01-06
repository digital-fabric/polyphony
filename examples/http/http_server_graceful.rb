# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/http'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

server = spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
end

trap('SIGHUP') do
  puts 'got hup'
  server.interrupt
end

puts "pid: #{Process.pid}"
puts 'Send HUP to stop gracefully'
puts 'Listening on port 1234...'

suspend