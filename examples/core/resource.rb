# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

resource_count = 0
Pool = Polyphony::ResourcePool.new(limit: 3) do
  :"resource#{resource_count += 1}"
end

def user(number)
  loop do
    # puts "user #{number} >"
    Pool.acquire do |r|
      puts "user #{number} #{r.inspect} >"
      sleep(0.05 + rand * 0.2)
      puts "user #{number} #{r.inspect} <"
      # raise if rand > 0.9
      # STDOUT << '.'
      # puts "#{number}: #{r.inspect}"
    end
  end
end

3.times do |x|
  spin { user(x) }
end

t0 = Time.now
every(10) { puts "uptime: #{Time.now - t0}" }
