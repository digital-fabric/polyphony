# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

Exception.__disable_sanitized_backtrace__ = true

TIME_URI = 'https://ui.realiteq.net/'

def get_server_time
  json = Polyphony::HTTP::Agent.get(TIME_URI, query: { q: :time }).json
  puts "*" * 40
  p json
end

X = 1
puts "Making #{X} requests..."
t0 = Time.now
supervise do |s|
  X.times {
    s.spin {
      get_server_time
    }
  }
end
# get_server_time
elapsed = Time.now - t0
puts "count: #{X} elapsed: #{elapsed} rate: #{X / elapsed} reqs/s"
