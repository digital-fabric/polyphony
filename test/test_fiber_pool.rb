# frozen_string_literal: true

require_relative 'helper'

class FiberPoolTest < Minitest::Test
  Pool = Polyphony::FiberPool

  def teardown
    Pool.reset!
    super
  end

  def test_fiber_allocation
    assert_equal 0, Pool.available_count
    assert_equal 0, Pool.total_count
    assert_equal 0, Pool.checked_out_count

    values = []
    f = Pool.allocate { values << :foo }
    assert_kind_of Fiber, f
    assert_equal 0, Pool.available_count
    assert_equal 1, Pool.total_count
    assert_equal 1, Pool.checked_out_count

    f.schedule
    snooze

    assert_equal [:foo], values
  end

  def test_reallocation
    values = []
    fibers = []
    f1 = Pool.allocate { values << :foo }
    f2 = Pool.allocate { values << :bar }
    assert f1 != f2

    assert_equal 0, Pool.available_count
    assert_equal 2, Pool.total_count
    assert_equal 2, Pool.checked_out_count

    f1.schedule
    snooze

    assert_equal [:foo], values
    assert_equal 1, Pool.available_count
    assert_equal 2, Pool.total_count
    assert_equal 1, Pool.checked_out_count

    f3 = Pool.allocate { values << :baz }

    assert_equal f1, f3
    assert_equal 0, Pool.available_count
    assert_equal 2, Pool.total_count
    assert_equal 2, Pool.checked_out_count

    f2.schedule
    f3.schedule
    snooze

    assert_equal [:foo, :bar, :baz], values
    assert_equal 2, Pool.available_count
    assert_equal 2, Pool.total_count
    assert_equal 0, Pool.checked_out_count
  end
end
