# frozen_string_literal: true

require_relative 'helper'

class FiberPoolTest < Minitest::Test
  Pool = Polyphony::FiberPool

  def teardown
    Pool.reset!
    super
  end

  def test_fiber_allocation
    assert_equal 0, Pool.stats[:available]
    assert_equal 0, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]

    values = []
    f = Pool.allocate { values << :foo }
    assert_kind_of Fiber, f
    assert_equal 0, Pool.stats[:available]
    assert_equal 1, Pool.stats[:total]
    assert_equal 1, Pool.stats[:checked_out]

    f.schedule
    snooze

    assert_equal [:foo], values
  end

  def test_reallocation
    values = []
    f1 = Pool.allocate { values << :foo }
    f2 = Pool.allocate { values << :bar }
    assert f1 != f2

    assert_equal 0, Pool.stats[:available]
    assert_equal 2, Pool.stats[:total]
    assert_equal 2, Pool.stats[:checked_out]

    f1.schedule
    snooze

    assert_equal [:foo], values
    assert_equal 1, Pool.stats[:available]
    assert_equal 2, Pool.stats[:total]
    assert_equal 1, Pool.stats[:checked_out]

    f3 = Pool.allocate { values << :baz }

    assert_equal f1, f3
    assert_equal 0, Pool.stats[:available]
    assert_equal 2, Pool.stats[:total]
    assert_equal 2, Pool.stats[:checked_out]

    f2.schedule
    f3.schedule
    snooze

    assert_equal %i[foo bar baz], values
    assert_equal 2, Pool.stats[:available]
    assert_equal 2, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]
  end

  def test_value_passing
    values = []
    f = Pool.allocate do |x|
      loop do
        values << x
        x = Fiber.main.transfer
      end
    end
    f.transfer :foo
    f.transfer :bar

    assert_equal %i[foo bar], values
  end

  def test_error_propagation_to_main_fiber
    error = nil
    f = Pool.allocate { raise 'foo' }
    begin
      f.schedule
      suspend
    rescue Exception => e
      error = e
    end
    assert_kind_of Exception, error
  end

  def test_error_propagation_to_calling_fiber
    error = nil
    f1 = Pool.allocate do
      f2 = Pool.allocate { raise 'foo' }
      f2.schedule
      suspend
    rescue Exception => e
      error = e
    end

    f1.schedule
    3.times { snooze }
    assert_kind_of Exception, error
  end

  def test_error_bubbling_up
    error = nil
    f1 = Pool.allocate do
      f2 = Pool.allocate { raise 'foo' }
      f2.schedule
      suspend
    end

    f1.schedule

    begin
      3.times { snooze }
    rescue Exception => e
      error = e
    end

    assert_kind_of Exception, error
  end

  def test_compact
    10.times { Pool.allocate { snooze }.schedule }
    assert_equal 0, Pool.stats[:available]
    assert_equal 10, Pool.stats[:total]
    assert_equal 10, Pool.stats[:checked_out]
    snooze
    snooze
    assert_equal 10, Pool.stats[:available]
    assert_equal 10, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]
    
    3.times { Pool.allocate { snooze }.schedule }
    assert_equal 7, Pool.stats[:available]
    assert_equal 10, Pool.stats[:total]
    assert_equal 3, Pool.stats[:checked_out]

    Pool.compact
    snooze

    assert_equal 0, Pool.stats[:available]
    assert_equal 3, Pool.stats[:total]
    assert_equal 3, Pool.stats[:checked_out]

    snooze

    assert_equal 3, Pool.stats[:available]
    assert_equal 3, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]

    Pool.compact
    assert_equal 3, Pool.stats[:available]
    assert_equal 3, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]

    snooze
    assert_equal 0, Pool.stats[:available]
    assert_equal 0, Pool.stats[:total]
    assert_equal 0, Pool.stats[:checked_out]
  end
end
