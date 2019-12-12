# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'

Polyphony::HTTP::Server.serve('0.0.0.0', 1234) do |req|
  req.respond("Hello world!\n")
end
