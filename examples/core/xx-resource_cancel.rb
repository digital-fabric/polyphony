# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

resource_count = 0
Pool = Polyphony::ResourcePool.new(limit: 3) do
  +"resource#{resource_count += 1}"
end

def user(number)
  loop do
    Polyphony::CancelScope.new(timeout: 0.2) do |scope|
      scope.on_cancel { puts "#{number} (cancelled)" }
      Pool.acquire do |r|
        puts "#{number} #{r.inspect} >"
        sleep(0.1 + rand * 0.2)
        puts "#{number} #{r.inspect} <"
      end
    end
  end
end

10.times do |x|
  spin { user(x + 1) }
end

t0 = Time.now
throttled_loop(0.1) { puts "uptime: #{Time.now - t0}" }