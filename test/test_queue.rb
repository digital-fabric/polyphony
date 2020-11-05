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

  def test_fiber_removal_from_queue_simple
    f1 = spin { @queue.shift }
    
    # let fibers run
    snooze

    f1.stop
    snooze

    @queue << :foo
    assert_nil f1.await
  end

  def test_queue_size
    assert_equal 0, @queue.size

    @queue.push 1
    
    assert_equal 1, @queue.size

    @queue.push 2
    
    assert_equal 2, @queue.size

    @queue.shift

    assert_equal 1, @queue.size

    @queue.shift

    assert_equal 0, @queue.size
  end
end

class CappedQueueTest < MiniTest::Test
  def setup
    super
    @queue = Polyphony::Queue.new
    @queue.cap(3)
  end

  def test_capped?
    q = Polyphony::Queue.new
    assert_nil q.capped?

    q.cap(3)
    assert_equal 3, q.capped?
  end

  def test_initalize_with_cap
    q = Polyphony::Queue.new(42)
    assert_equal 42, q.capped?
  end

  def test_capped_push
    buffer = []
    a = spin do
      (1..5).each do |i|
        @queue.push(i)
        buffer << :"p#{i}"
      end
      @queue.push :stop
    end

    snooze

    b = spin_loop do
      i = @queue.shift
      raise Polyphony::Terminate if i == :stop
      buffer << :"s#{i}"
    end

    Fiber.join(a, b)
    assert_equal [:p1, :p2, :s1, :p3, :s2, :p4, :s3, :p5, :s4, :s5], buffer
  end

  def test_capped_multi_push
    buffer = []
    a = spin(:a) do
      (1..3).each do |i|
        @queue.push(i)
        buffer << :"p#{i}"
      end
    end

    buffer = []
    b = spin(:b) do
      (4..6).each do |i|
        @queue.push(i)
        buffer << :"p#{i}"
      end
      @queue.push :stop
    end

    c = spin_loop do
      i = @queue.shift
      raise Polyphony::Terminate if i == :stop
      buffer << :"s#{i}"
      snooze
    end

    Fiber.join(a, b, c)
    assert_equal [:p1, :p4, :s1, :p5, :p2, :s4, :p3, :s5, :p6, :s2, :s3, :s6], buffer
  end

  def test_capped_clear
    buffer = []
    a = spin(:a) do
      (1..5).each do |i|
        @queue.push(i)
        buffer << i
      end
    end

    snooze while buffer.size < 3
    @queue.clear
    buffer << :clear

    a.join
    assert_equal [1, 2, 3, :clear, 4, 5], buffer
  end

  def test_capped_delete
    buffer = []
    a = spin(:a) do
      (1..5).each do |i|
        @queue.push(i)
        buffer << i
      end
    end

    i = 0
    spin_loop do
      i += 1
      snooze 
    end

    5.times { snooze }
    assert_equal 5, i
    @queue.delete 1
    buffer << :"d#{i}"
    3.times { snooze }
    assert_equal 8, i
    @queue.delete 2
    buffer << :"d#{i}"

    a.join
    assert_equal [1, 2, 3, :d5, 4, :d8, 5], buffer
  end
end