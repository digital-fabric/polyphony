# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

class GenServer
  def self.start(receiver, *args)
    coroutine = spawn do
      state = receiver.initial_state(*args)
      loop do
        msg = receive
        reply, state = receiver.send(msg[:method], state, *msg[:args])
        msg[:from] << reply unless reply == :noreply
      end
    end
    build_api(coroutine, receiver)
    coroutine
  end

  def self.build_api(coroutine, receiver)
    receiver.methods(false).each do |m|
      if m =~ /!$/
        coroutine.define_singleton_method(m) do |*args|
          GenServer.cast(coroutine, m, *args)
        end
      else
        coroutine.define_singleton_method(m) do |*args|
          GenServer.call(coroutine, m, *args)
        end
      end
    end
  end

  def self.cast(process, method, *args)
    process << {from: Rubato::Coroutine.current, method: method, args: args}
  end

  def self.call(process, method, *args)
    process << {from: Rubato::Coroutine.current, method: method, args: args}
    receive
  end
end

module Map
  def self.initial_state(hash = {})
    hash
  end

  def self.get(state, key)
    return state[key], state
  end

  def self.put!(state, key, value)
    state[key] = value
    return :noreply, state
  end
end

map_server = GenServer.start(Map)

spawn do
  puts "getting value from map server"
  v = map_server.get(:foo)
  puts "v: #{v.inspect}"

  puts "getting value in map server"
  map_server.put!(:foo, 42)

  puts "getting value from map server"
  v = map_server.get(:foo)
  puts "v: #{v.inspect}"
end