# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

class Number
  def initialize(id)
    @id = id
  end

  def greet(other)
    puts "You are number #{other}, I am number #{@id}"
    sleep(0.05 + rand * 0.2)
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

3.times { |x| spin { meet(x) } }

t0 = Time.now
every(10) { puts "uptime: #{Time.now - t0}" }
