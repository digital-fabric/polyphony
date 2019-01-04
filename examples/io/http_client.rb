# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')
Agent = import('../../lib/polyphony/http/agent')

def get_server_time
  Agent.get('https://ui.realiteq.net/', q: :time).json
end

X = 50
puts "Making #{X} requests..."
t0 = Time.now
supervise do |s|
  X.times { get_server_time }
end
elapsed = Time.now - t0
puts "count: #{X} elapsed: #{elapsed} rate: #{X / elapsed} reqs/s"
