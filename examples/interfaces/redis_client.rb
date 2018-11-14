# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Redis   = import('../../lib/rubato/interfaces/redis')

redis = Redis::Connection.new

Rubato.async do
  Rubato.await redis.connect
  puts "connected"

  puts "redis server time: #{Rubato.await redis.time}"

  puts "abc = #{Rubato.await redis.get('abc')}"

  puts "updating value..."
  Rubato.await redis.set('abc', Time.now.to_s)

  puts "abc = #{Rubato.await redis.get('abc')}"

  redis.close
end