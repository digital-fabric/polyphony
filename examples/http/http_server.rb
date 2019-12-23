# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/http'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  rescue Exception => e
    p e
  end
end

spin do
  throttled_loop(1) do
    puts "#{Time.now} coprocess count: #{Polyphony::Coprocess.list.size}"
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
