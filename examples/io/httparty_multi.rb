# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'

url = 'http://realiteq.net/?q=time'
results = []

t0 = Time.now
move_on_after(3) do
  supervise do |s|
    10.times { s.spawn { loop { results << HTTParty.get(url); STDOUT << '.' } } }
  end
  puts "done"
end
puts "got #{results.size} (#{results.size / (Time.now - t0)}/s)"
