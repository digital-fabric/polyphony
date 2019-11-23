# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'httparty'

url = 'http://127.0.0.1:4411/?q=time'
results = []

t0 = Time.now
move_on_after(3) do
  supervise do |s|
    10.times do
      s.spin do
        loop do
          STDOUT << '!'
          if (result = HTTParty.get(url))
            results << result
            STDOUT << '.'
          end
        rescue StandardError => e
          p e
        end
      end
    end
  end
  puts 'done'
end
puts "got %<count>d (%<rate>0.1f reqs/s)" % {
  count: results.size,
  rate:  results.size / (Time.now - t0)
}
