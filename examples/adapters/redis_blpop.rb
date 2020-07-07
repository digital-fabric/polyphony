# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/redis'
# require 'redis'

redis = Redis.new(host: ENV['REDISHOST'] || 'localhost')

redis.lpush("queue_key", "omgvalue")
puts "len: #{redis.llen("queue_key")}"
result = redis.blpop("queue_key")
puts result.inspect
