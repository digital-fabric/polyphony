# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
import('../../lib/rubato/interfaces/redis')

redis = Redis.new

spawn do
  t0 = Time.now
  1000.times { redis.get('abc') }
  puts "get rate: #{1000 / (Time.now - t0)} reqs/s"

  puts "abc = #{redis.get('abc')}"

  puts "updating value..."
  redis.set('abc', Time.now.to_s)

  puts "abc = #{redis.get('abc')}"
end