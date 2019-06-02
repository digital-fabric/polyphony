# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'

url = 'http://127.0.0.1:4411/?q=time'
results = []

t0 = Time.now
move_on_after(3) do
  supervise do |s|
    10.times do
      s.spawn do
        loop do
          STDOUT << '!'
          if (result = HTTParty.get(url))
            results << result
            STDOUT << '.'
          end
        rescue => e
          p e
        end
      end
    end
  end
  puts "done"
end
puts "got #{results.size} (#{results.size / (Time.now - t0)}/s)"
