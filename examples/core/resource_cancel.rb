# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

resource_count = 0
Pool = Polyphony::ResourcePool.new(limit: 3) do
  :"resource#{resource_count += 1}"
end

def user(number)
  loop do
    move_on_after(0.2) do |scope|
      scope.when_cancelled do
        puts "#{number} (cancelled)"
      end
      
      Pool.acquire do |r|
        scope.disable
        puts "#{number} #{r.inspect} >"
        sleep(0.4 + rand * 0.2)
        puts "#{number} #{r.inspect} <"
      end
    end
  end
end

6.times do |x|
  spin { user(x) }
end

t0 = Time.now
every(10) { puts "uptime: #{Time.now - t0}" }
