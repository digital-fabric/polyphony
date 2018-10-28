# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

resource_count = 0
Pool = Nuclear::ResourcePool.new(limit: 3) do
  :"resource#{resource_count += 1}"
end

def user(number)
  loop do
    # puts "user #{number} >"
    Pool.acquire do |r|
      # puts "user #{number} #{r.inspect} >"
      await sleep(0.05 + rand * 0.2)
      STDOUT << '.'
      # puts "#{number}: #{r.inspect}"
    end
  end
end

100.times do |x|
  spawn { user(x) }
end

t0 = Time.now
every(10) { puts "uptime: #{Time.now - t0}" }
