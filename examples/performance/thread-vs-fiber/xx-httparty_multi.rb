# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'

URL = 'http://worldtimeapi.org/api/timezone/Europe/Paris'

def get_time(results)
  loop do
    STDOUT << '!'
    if (res = HTTParty.get(URL))
      results << res
      STDOUT << '.'
    end
  rescue StandardError => e
    p e
  end
end

t0 = Time.now
results = []
move_on_after(3) do
  supervise do |s|
    10.times do
      s.spin { get_time(results) }
    end
  end
  puts 'done'
end

puts format(
  'got %<count>d (%<rate>0.1f reqs/s)',
  count: results.size,
  rate:  results.size / (Time.now - t0)
)
