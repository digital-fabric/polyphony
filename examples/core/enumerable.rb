# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

module Enumerable
  def map_concurrently(&block)
    spin do
      results = []
      each_with_index do |i, idx|
        spin { results[idx] = block.(i) }
      end
      Fiber.current.await_all_children
      results
    end.await
  end

  def each_concurrently(max_fibers: nil, &block)
    return each_concurrently_with_fiber_pool(max_fibers, &block) if max_fibers

    spin do
      results = []
      each do |i|
        spin(&block).schedule(i)
      end
      Fiber.current.await_all_children
    end.await
    self
  end

  def each_concurrently_with_fiber_pool(max_fibers, &block)
    spin do
      fiber_count = 0
      workers = []
      each do |i|
        if fiber_count < max_fibers
          workers << spin do
            loop do
              item = receive
              break if item == :__stop__
              block.(item)
            end
          end
        end

        fiber = workers.shift
        fiber << i
        workers << fiber
      end
      workers.each { |f| f << :__stop__ }
      Fiber.current.await_all_children
    end.await
    self
  end
end

o = 1..3
o.each_concurrently(max_fibers: 2) do |i|
  puts "#{Fiber.current} sleep #{i}"
  sleep(i)
  puts "wakeup #{i}"
end
