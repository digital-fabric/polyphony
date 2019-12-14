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
end