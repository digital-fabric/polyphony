# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

def get_server_time
  Polyphony::HTTP::Agent.get('https://ui.realiteq.net/', q: :time).json
end

X = 10
puts "Making #{X} requests..."
t0 = Time.now
supervise do |s|
  X.times { s.spawn { get_server_time } }
end
elapsed = Time.now - t0
puts "count: #{X} elapsed: #{elapsed} rate: #{X / elapsed} reqs/s"