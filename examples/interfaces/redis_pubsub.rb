# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')
import('../../lib/polyphony/extensions/redis')

spawn do
  redis = Redis.new
  redis.subscribe('redis-channel') do |on|
    on.message do |channel, message|
      puts "##{channel}: #{message}"
      redis.unsubscribe if message == "exit"
    end
  end
end

spawn do
  redis = Redis.new
  move_on_after(3) do
    throttled_loop(1) do
      redis.publish('redis-channel', Time.now)
    end
  end
  redis.publish('redis-channel', 'exit')
end