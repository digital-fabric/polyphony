# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'
require 'json'

def get_time(tzone)
  res = HTTParty.get("http://worldtimeapi.org/api/timezone/#{tzone}")
  return '- failed -' unless res.ok?

  json = JSON.parse(res.body)
  Time.parse(json['datetime'])
end

zones = %w{
  Europe/London Europe/Paris Europe/Bucharest America/New_York Asia/Bangkok
}
# zones.each do |tzone|
#   spin do
#     time = get_time(tzone)
#     puts "Time in #{tzone}: #{time}"
#   end
# end

# suspend

def get_times(zones)
  Polyphony::Supervisor.new do |s|
    zones.each do |tzone|
      s.spin { [tzone, get_time(tzone)] }
    end
  end
end

get_times(zones).await.each do |tzone, time|
  puts "Time in #{tzone}: #{time}"
end
