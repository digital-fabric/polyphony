# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

class ::Enumerator
  def spin
    map { |i| Object.spin { yield i } }
  end

  def concurrently(max_fibers: nil, &block)
    return each_concurrently_with_fiber_pool(max_fibers, &block) if max_fibers

    results = []
    fibers = []
    each_with_index do |i, idx|
      fibers << Object.spin { results[idx] = block.(i) }
    end
    Fiber.await(fibers)
    results
  end

  private

  def each_concurrently_with_fiber_pool(max_fibers, &block)
    fiber_count = 0
    results = []
    workers = []

    each_with_index do |i, idx|
      if fiber_count < max_fibers
        workers << Object.spin do
          loop do
            item, idx = receive
            break if item == :__stop__
            results[idx] = block.(item)
          end
        end
      end

      fiber = workers.shift
      fiber << [i, idx]
      workers << fiber
    end
    workers.each { |f| f << :__stop__ }
    Fiber.current.await_all_children
    results
  end
end

a = [1, 2, 3]

# ff = a.map do |i|
#   spin do
#     puts "#{Fiber.current.inspect} #{i} >>"
#     sleep rand(0.1..0.2)
#     puts "#{Fiber.current.inspect} #{i} <<"
#   end
# end

# Fiber.await(*ff)

# puts; puts '*' * 40; puts

# ff = a.each.spin do |i|
#   puts "#{Fiber.current.inspect} #{i} >>"
#   sleep 0.1
#   puts "#{Fiber.current.inspect} #{i} <<"
# end

# Fiber.await(*ff)

# puts; puts '*' * 40; puts

# ff = a.each.concurrently do |i|
#   puts "#{Fiber.current.inspect} #{i} >>"
#   sleep 0.1
#   puts "#{Fiber.current.inspect} #{i} <<"
#   i * 10
# end
# p ff: ff

puts; puts '*' * 40; puts

ff = a.each.concurrently(max_fibers: 2) do |i|
  puts "#{Fiber.current.inspect} #{i} >>"
  sleep i
  puts "#{Fiber.current.inspect} #{i} <<"
  i * 10
end

p ff: ff
