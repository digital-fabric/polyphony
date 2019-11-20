# frozen_string_literal: true

f = Fiber.new do
  raise 'hi'
end

f.resume

puts 'done'
