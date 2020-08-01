# frozen_string_literal: true

require 'httparty'

URL = 'http://worldtimeapi.org/api/timezone/Europe/Paris'
results = Queue.new

t0 = Time.now
threads = []
10.times do
  threads << Thread.new do
    loop do
      STDOUT << '!'
      if (result = HTTParty.get(URL))
        results << result
        STDOUT << '.'
      end
    end
  end
end

sleep 3
threads.each(&:kill)
puts 'done'
puts format(
  'got %<count>d (%<rate>0.1f reqs/s)',
  count: results.size,
  rate:  results.size / (Time.now - t0)
)
