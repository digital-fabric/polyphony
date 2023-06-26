# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

# Based on the design of Elixir's GenStage

class Producer
  def initialize(mod, *a, **b)
    extend(mod)
    setup(*a, **b)
    @_fiber = spin do
      receive_loop do |msg|
        case msg[:kind]
        when :demand
          items = handle_demand(msg[:limit])
          msg[:peer] << items
        end
      end
    end
  end

  def <<(msg)
    @_fiber << msg
  end
end

module Counter
  def setup(counter = 0)
    @counter = counter
  end

  def handle_demand(demand)
    events = (@counter...@counter + demand).to_a
    @counter += demand
    events
  end
end

counter = Producer.new(Counter, 0)

class Consumer
  def initialize(mod, *a, **b)
    extend(mod)
    setup(*a, **b) if respond_to?(:setup)
    @_fiber = spin do
      while true
        items = get_items
        handle_items(items)
      end
    end

    @max_demand = 10
    @min_demand = 5
  end

  def subscribe(upstream)
    @upstream = upstream
  end

  private

  def get_items
    send_demand(@max_demand) if !@sent_demand
    items = receive
    send_demand(@min_demand)
    items
  end

  def send_demand(demand)
    if @upstream
      @upstream << { peer: Fiber.current, kind: :demand, limit: demand }
      @sent_demand = true
    else
      sleep 0.1
    end
  end
end

module Printer
  def handle_items(items)
    sleep 1
    puts "got: #{items.join(' ')}"
  end
end

# counter << { peer: Fiber.current, kind: :demand, limit: 10 }
# r = receive

# p r: r

# counter << { peer: Fiber.current, kind: :demand, limit: 10 }
# r = receive
# p r: r

printer = Consumer.new(Printer)
printer.subscribe(counter)

sleep
