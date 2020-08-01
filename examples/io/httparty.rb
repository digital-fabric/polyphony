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

def get_times(zones)
  fibers = zones.map do |tzone|
    spin { [tzone, get_time(tzone)] }
  end
  Fiber.await(*fibers)
end

get_times(zones).each do |tzone, time|
  puts "Time in #{tzone}: #{time}"
end
