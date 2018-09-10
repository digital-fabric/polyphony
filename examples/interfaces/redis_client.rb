# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')
Redis   = import('../../lib/nuclear/interfaces/redis')

redis = Redis::Connection.new

Nuclear.async do
  Nuclear.await redis.connect
  puts "connected"

  puts "redis server time: #{Nuclear.await redis.time}"

  puts "abc = #{Nuclear.await redis.get('abc')}"

  puts "updating value..."
  Nuclear.await redis.set('abc', Time.now.to_s)

  puts "abc = #{Nuclear.await redis.get('abc')}"

  redis.close
end