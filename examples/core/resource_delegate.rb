# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

class Number
  def initialize(id)
    @id = id
  end

  def greet(other)
    puts "You are number #{other}, I am number #{@id}"
    sleep rand(0.2..0.3)
  end
end

resource_count = 0
Pool = Polyphony::ResourcePool.new(limit: 3) do
  Number.new(resource_count += 1)
end

def meet(number)
  loop do
    Pool.greet(number)
  end
end

(4..10).each { |x| spin { meet(x) } }

sleep 1