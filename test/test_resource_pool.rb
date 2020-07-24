# frozen_string_literal: true

require_relative 'helper'

class ResourcePoolTest < MiniTest::Test
  def test_resource_pool_limit
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 2) { resources.shift }

    assert_equal 2, pool.limit
    assert_equal 0, pool.available
    assert_equal 0, pool.size

    results = []
    4.times { |i|
      spin(:"foo#{i}") {
        pool.acquire { |resource|
          results << resource
          snooze
        }
      }
    }
    Fiber.current.await_all_children
    assert_equal 2, pool.limit
    assert_equal 2, pool.available
    assert_equal 2, pool.size
    assert_equal ['a', 'b', 'a', 'b'], results
  end

  def test_single_resource_limit
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 1) { resources.shift }

    results = []
    10.times {
      spin {
        snooze
        pool.acquire { |resource|
          results << resource
          snooze
        }
      }
    }
    21.times { snooze }

    assert_equal ['a'] * 10, results
  end

  def test_failing_allocator
    pool = Polyphony::ResourcePool.new(limit: 4) { raise }

    assert_raises { pool.acquire { } }
  end

  def test_method_delegation
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 2) { resources.shift }

    assert_respond_to pool, :upcase
    assert_equal 'A', pool.upcase
  end

  def test_preheat
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 2) { resources.shift }

    assert_equal 2, pool.limit
    assert_equal 0, pool.size

    pool.preheat!
    assert_equal 2, pool.size
  end

  def test_reentrant_resource_pool
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 1) { resources.shift }

    results = []
    pool.acquire do |r|
      results << r
      2.times do
        pool.acquire do |r|
          results << r
        end
      end
    end
    assert_equal ['a']*3, results
  end

  def test_overloaded_resource_pool
    pool = Polyphony::ResourcePool.new(limit: 1) { 1 }

    buf = []
    fibers = 2.times.map do |i|
      spin(:"foo#{i}") do
        2.times do
          pool.acquire do |r|
            buf << r
            snooze
          end
        end
      end
    end
    Fiber.current.await_all_children

    assert_equal [1, 1, 1, 1], buf
  end
end