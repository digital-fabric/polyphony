# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

module GenServer
  module_function

  def start(receiver, *args)
    fiber = spin do
      state = receiver.initial_state(*args)
      loop do
        msg = receive
        reply, state = receiver.send(msg[:method], state, *msg[:args])
        msg[:from] << reply unless reply == :noreply
      end
    end
    build_api(fiber, receiver)
    fiber
  end

  def build_api(fiber, receiver)
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

  def cast(process, method, *args)
    process << {
      from:   Fiber.current,
      method: method,
      args:   args
    }
  end

  def call(process, method, *args)
    process << {
      from:   Fiber.current,
      method: method,
      args:   args
    }
    receive
  end
end

# In a generic server the state is not held in an instance variable but rather
# passed as the first parameter to method calls. The return value of each method
# is an array consisting of the result and the potentially mutated state.
module Map
  module_function

  def initial_state(hash = {})
    hash
  end

  def get(state, key)
    [state[key], state]
  end

  def put!(state, key, value)
    state[key] = value
    [:noreply, state]
  end
end

# start server with initial state
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
