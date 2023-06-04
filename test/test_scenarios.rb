# frozen_string_literal: true

require_relative 'helper'

class ScenarioTest < MiniTest::Test
  def test_monocrono
    count = 256

    workers = {}
    count.times do |i|
      factor = i + 1
      workers[i] = spin_loop do
        peer, num = receive
        peer << (num * factor)
      end
    end

    router = spin_loop do
      peer, id, num = receive
      worker = workers[id]
      worker << [peer, num]
    end

    results = []
    (count * 256).times do
      id = rand(count)
      num = rand(1000)
      router << [Fiber.current, id, num]
      result = receive
      assert_equal num * (id + 1), result
    end
  ensure
    workers.each_value do |w|
      w.kill
      w.join
    end
  end
end
