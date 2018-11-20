# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

resource_count = 0
Pool = Rubato::ResourcePool.new(limit: 3) do
  :"resource#{resource_count += 1}"
end

async def user(number)
  loop do
    # puts "user #{number} >"
    Pool.acquire do |r|
      puts "user #{number} #{r.inspect} >"
      await sleep(0.05 + rand * 0.2)
      # STDOUT << '.'
      # puts "#{number}: #{r.inspect}"
    end
  end
end

100.times do |x|
  spawn user(x)
end

t0 = Time.now
every(10) { puts "uptime: #{Time.now - t0}" }
