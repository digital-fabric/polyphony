# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

class GenServer
  def self.start(receiver, *args)
    fiber = spin do
      state = receiver.initial_state(*args)
      loop do
        msg = receive
        reply, state = receiver.send(msg[:method], state, *msg[:args])
        msg[:from] << reply unless reply == :noreply
      end
    end
    build_api(fiber, receiver)
    snooze
    fiber
  end

  def self.build_api(fiber, receiver)
    receiver.methods(false).each do |m|
      if m =~ /!$/
        fiber.define_singleton_method(m) do |*args|
          GenServer.cast(fiber, m, *args)
        end
      else
        fiber.define_singleton_method(m) do |*args|
          GenServer.call(fiber, m, *args)
        end
      end
    end
  end

  def self.cast(process, method, *args)
    process << {
      from:   Fiber.current,
      method: method,
      args:   args
    }
  end

  def self.call(process, method, *args)
    process << {
      from:   Fiber.current,
      method: method,
      args:   args
    }
    receive
  end
end

module Map
  def self.initial_state(hash = {})
    hash
  end

  def self.get(state, key)
    [state[key], state]
  end

  def self.put!(state, key, value)
    state[key] = value
    [:noreply, state]
  end
end

map_server = GenServer.start(Map, {foo: :bar})

puts 'getting value from map server'
v = map_server.get(:foo)
puts "value: #{v.inspect}"

puts 'putting value in map server'
map_server.put!(:foo, :baz)

puts 'getting value from map server'
v = map_server.get(:foo)
puts "value: #{v.inspect}"

map_server.stop
