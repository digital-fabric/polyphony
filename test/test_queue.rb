# frozen_string_literal: true

require_relative 'helper'

class QueueTest < MiniTest::Test
  def setup
    super
    @queue = Polyphony::Queue.new
  end

  def test_pop
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
  end

  def test_empty?
    assert @queue.empty?
    
    @queue << :foo
    assert !@queue.empty?

    assert_equal :foo, @queue.shift
    assert @queue.empty?
  end
end