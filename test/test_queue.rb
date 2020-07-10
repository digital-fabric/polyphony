# frozen_string_literal: true

require_relative 'helper'

class QueueTest < MiniTest::Test
  def setup
    super
    @queue = Polyphony::Queue.new
  end

  def test_push_shift
    spin {
      @queue << 42
    }
    v = @queue.shift
    assert_equal 42, v

    (1..4).each { |i| @queue << i }
    buf = []
    4.times { buf << @queue.shift }
    assert_equal [1, 2, 3, 4], buf
  end

  def test_unshift
    @queue.push 1
    @queue.push 2
    @queue.push 3
    @queue.unshift 4

    buf = []
    buf << @queue.shift while !@queue.empty?

    assert_equal [4, 1, 2, 3], buf
  end

  def test_multiple_waiters
    a = spin { @queue.shift }
    b = spin { @queue.shift }

    @queue << :foo
    @queue << :bar

    assert_equal [:foo, :bar], Fiber.await(a, b)
  end

  def test_multi_thread_usage
    t = Thread.new { @queue.push :foo }
    assert_equal :foo, @queue.shift
  end

  def test_shift_each
    (1..4).each { |i| @queue << i }
    buf = []
    @queue.shift_each { |i| buf << i }
    assert_equal [1, 2, 3, 4], buf

    buf = []
    @queue.shift_each { |i| buf << i }
    assert_equal [], buf
  end

  def test_shift_all
    (1..4).each { |i| @queue << i }
    buf = @queue.shift_all
    assert_equal [1, 2, 3, 4], buf

    buf = @queue.shift_all
    assert_equal [], buf
  end

  def test_empty?
    assert @queue.empty?
    
    @queue << :foo
    assert !@queue.empty?

    assert_equal :foo, @queue.shift
    assert @queue.empty?
  end

  def test_fiber_removal_from_queue
    f1 = spin { @queue.shift }
    f2 = spin { @queue.shift }
    f3 = spin { @queue.shift }
    
    # let fibers run
    snooze

    f2.stop
    snooze

    @queue << :foo
    @queue << :bar

    assert_equal :foo, f1.await
    assert_nil f2.await
    assert_equal :bar, f3.await
  end
end