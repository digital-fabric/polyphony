# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/redis'

redis = Redis.new

X = 10

t0 = Time.now
X.times { redis.get('abc') }
puts "get rate: #{X / (Time.now - t0)} reqs/s"

puts "abc = #{redis.get('abc')}"

puts 'updating value...'
redis.set('abc', Time.now.to_s)

puts "abc = #{redis.get('abc')}"
