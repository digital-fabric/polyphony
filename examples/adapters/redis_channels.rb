# frozen_string_literal: true

require 'redis'
require_relative '../../lib/polyphony/adapters/redis'
require_relative '../../lib/polyphony'
require_relative '../../lib/polyphony/core/channel'

class RedisChannel < Polyphony::Channel
  def self.publish_connection
    @publish_connection ||= Redis.new
  end

  def self.subscribe_connection
    @subscribe_connection ||= Redis.new
  end

  CHANNEL_MASTER_TOPIC = 'channel_master'

  def self.start_monitor
    @channels = {}
    @monitor = spin do
      p start_monitor: 1
      subscribe_connection.subscribe(CHANNEL_MASTER_TOPIC) do |on|
        p start_monitor: 2
        on.message do |topic, message|
          p start_monitor: 3, topic: topic, message: message
          message = Marshal.load(message)
          if CHANNEL_MASTER_TOPIC
            handle_master_message(message)
          else
            handle_channel_message(topic, message)
          end
        end
      end
    end
  end

  def self.stop_monitor
    p stop_monitor: 1
    @monitor&.interrupt
  end

  def self.handle_master_message(message)
    case message[:kind]
    when :subscribe
      subscribe_connection.subscribe(message[:topic])
    when :unsubscribe
      subscribe_connection.unsubscribe(message[:topic])
    end
  end

  def self.handle_channel_message(topic, message)
    channel = @channels[topic]
    channel&.did_receive(message)
  end

  def self.watch(channel)
    @channels[channel.topic] = channel
    spin do
      publish_connection.publish(CHANNEL_MASTER_TOPIC, Marshal.dump(
                                                         kind:  :subscribe,
                                                         topic: channel.topic
                                                       ))
    end
  end

  def self.unwatch(channel)
    @channels.delete(channel.topic)
    spin do
      publish_connection.publish(CHANNEL_MASTER_TOPIC, Marshal.dump(
                                                         kind:  :unsubscribe,
                                                         topic: channel.topic
                                                       ))
    end
  end

  def self.channel_topic(channel)
    "channel_#{channel.object_id}"
  end

  attr_reader :topic

  def initialize(topic)
    @topic = topic
    @waiting_queue = []
    RedisChannel.watch(self)
  end

  def close
    super
    RedisChannel.unwatch(self)
  end

  def <<(o)
    RedisChannel.publish_connection.publish(@topic, Marshal.dump(o))
  end

  def did_receive(o)
    @waiting_queue.shift&.schedule(o)
  end

  def receive
    @waiting_queue << Fiber.current
    suspend
  end
end

RedisChannel.start_monitor
channel = RedisChannel.new('channel1')

spin do
  loop do
    message = channel.receive
    puts "got message: #{message}"
  end
end

spin do
  move_on_after(3) do
    p :move_on_after
    throttled_loop(1) do
      # p :throttled_loop
      channel << Time.now
    end
  end
  p :done
  channel.close
  RedisChannel.stop_monitor
end

suspend