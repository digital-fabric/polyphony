# frozen_string_literal: true

require 'redis'
require_relative '../../lib/polyphony/adapters/redis'
require_relative '../../lib/polyphony'


redis = Redis.new(host: ENV['REDISHOST'] || 'localhost')

redis.lpush("queue_key", "omgvalue")
puts "len: #{redis.llen("queue_key")}"
result = redis.blpop("queue_key")
puts result.inspect
