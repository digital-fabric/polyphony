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
    4.times {
      spin {
        snooze
        pool.acquire { |resource|
          results << resource
          snooze
        }
      }
    }
    2.times { snooze }
    assert_equal 2, pool.limit
    assert_equal 0, pool.available
    assert_equal 2, pool.size

    2.times { snooze }

    assert_equal ['a', 'b', 'a', 'b'], results

    2.times { snooze }

    assert_equal 2, pool.limit
    assert_equal 2, pool.available
    assert_equal 2, pool.size
  end

  def test_discard
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 2) { resources.shift }

    results = []
    4.times {
      spin {
        snooze
        pool.acquire { |resource|
          results << resource
          resource.__discard__ if resource == 'b'
          snooze
        }
      }
    }
    6.times { snooze }

    assert_equal ['a', 'b', 'a', 'a'], results
    assert_equal 1, pool.size
  end

  def test_add
    resources = [+'a', +'b']
    pool = Polyphony::ResourcePool.new(limit: 2) { resources.shift }

    pool << +'c'

    results = []
    4.times {
      spin {
        snooze
        pool.acquire { |resource|
          results << resource
          resource.__discard__ if resource == 'b'
          snooze
        }
      }
    }
    6.times { snooze }

    assert_equal ['c', 'a', 'c', 'a'], results
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
    20.times { snooze }

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

    pool.acquire do |r|
      assert_equal 'a', r
      pool.acquire do |r|
        assert_equal 'a', r
      end
    end
  end
end