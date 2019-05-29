# frozen_string_literal: true

require 'httparty'

url = 'http://realiteq.net/?q=time'
results = Queue.new

t0 = Time.now
threads = []
10.times do
  threads << Thread.new do
    loop do
      results << HTTParty.get(url); STDOUT << '.'
    end
  end
end

sleep 3
threads.each(&:kill)
puts "done"
puts "got #{results.size} (#{results.size / (Time.now - t0)}/s)"
