# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

Exception.__disable_sanitized_backtrace__ = true

TIME_URI = 'http://ui.realiteq.net/'

def get_server_time
  Polyphony::HTTP::Agent.get(TIME_URI, query: { q: :time }).json
end

X = 100
puts "Making #{X} requests..."
t0 = Time.now
supervise do |s|
  X.times { s.spin { get_server_time } }
end
elapsed = Time.now - t0
puts "count: #{X} elapsed: #{elapsed} rate: #{X / elapsed} reqs/s"
