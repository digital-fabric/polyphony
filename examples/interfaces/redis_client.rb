# frozen_string_literal: true
require 'modulation'

Redis =     import('../../lib/nuclear/interfaces/redis')
Reactor =   import('../../lib/nuclear/reactor')
extend      import('../../lib/nuclear/concurrency')

redis = Redis::Connection.new

async do
  await redis.connect
  puts "connected"

  puts "redis server time: #{await redis.time}"

  puts "abc = #{await redis.get('abc')}"

  puts "updating value..."
  await redis.set('abc', Time.now.to_s)

  puts "abc = #{await redis.get('abc')}"

  redis.close
end