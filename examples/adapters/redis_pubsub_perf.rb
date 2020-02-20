# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/redis'
require 'json'

X_SESSIONS = 1000
X_NODES = 10_000
X_SUBSCRIPTIONS_PER_SESSION = 100

$sessions = []
X_SESSIONS.times do
  $sessions << {
    subscriptions: X_SUBSCRIPTIONS_PER_SESSION.times.map do
      "node#{rand(X_NODES)}"
    end.uniq
  }
end

spin do
  redis = Redis.new
  redis.subscribe('events') do |on|
    on.message do |_, message|
      distribute_event(JSON.parse(message, symbolize_names: true))
    end
  end
end

$update_count = 0

def distribute_event(event)
  $update_count += 1
  # t0 = Time.now
  count = 0
  $sessions.each do |s|
    count += 1 if s[:subscriptions].include?(event[:path])
  end
  # elapsed = Time.now - t0
  # rate = X_SESSIONS / elapsed
  # puts "elapsed: #{elapsed} (#{rate}/s)" if $update_count % 100 == 0
end

spin do
  redis = Redis.new
  throttled_loop(1000) do
    redis.publish('events', { path: "node#{rand(X_NODES)}" }.to_json)
  end
end

spin do
  last_count = 0
  last_stamp = Time.now
  throttled_loop(1) do
    now = Time.now
    elapsed = now - last_stamp
    delta = $update_count - last_count
    puts "update rate: #{delta.to_f / elapsed}"
    last_stamp = now
    last_count = $update_count
  end
end

trap(:int) do
  puts 'bye...'
  exit!
end

suspend