# frozen_string_literal: true

require_relative 'helper'

class TimerMoveOnAfterTest < MiniTest::Test
  def setup
    super
    @timer = Polyphony::Timer.new(resolution: 0.01)
  end

  def teardown
    @timer.stop
    super
  end

  def test_timer_move_on_after
    t0 = Time.now
    v = @timer.move_on_after(0.1) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert_in_range 0.1..0.15, t1 - t0 if IS_LINUX
    assert_nil v
  end

  def test_timer_move_on_after_with_value
    t0 = Time.now
    v = @timer.move_on_after(0.01, with_value: :bar) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert_in_range 0.01..0.05, t1 - t0 if IS_LINUX
    assert_equal :bar, v
  end

  def test_timer_move_on_after_with_reset
    skip unless IS_LINUX

    t0 = Time.now
    v = @timer.move_on_after(0.1, with_value: :moved_on) do
      sleep 0.07
      @timer.reset
      sleep 0.07
      @timer.reset
      sleep 0.07
      nil
    end
    t1 = Time.now

    assert_nil v
    assert_in_range 0.12..0.4, t1 - t0
  end
end

class TimerCancelAfterTest < MiniTest::Test
  def setup
    super
    @timer = Polyphony::Timer.new(resolution: 0.01)
  end

  def teardown
    @timer.stop
    super
  end

  def test_timer_cancel_after
    t0 = Time.now

    assert_raises Polyphony::Cancel do
      @timer.cancel_after(0.01) do
        sleep 1
        :foo
      end
    end
    t1 = Time.now
    assert_in_range 0.01..0.04, t1 - t0 if IS_LINUX
  end

  def test_timer_cancel_after_with_reset
    buf = []
    @timer.cancel_after(0.15) do
      sleep 0.05
      buf << 1
      @timer.reset
      sleep 0.05
      buf << 2
      @timer.reset
      sleep 0.05
      buf << 3
      @timer.reset
      sleep 0.05
      buf << 4
    end
    assert_equal [1, 2, 3, 4], buf
  end

  class CustomException < Exception
  end

  def test_timer_cancel_after_with_custom_exception
    assert_raises CustomException do
      @timer.cancel_after(0.01, with_exception: CustomException) do
        sleep 1
        :foo
      end
    end

    begin
      err = nil
      @timer.cancel_after(0.01, with_exception: [CustomException, 'custom message']) do
        sleep 1
        :foo
      end
    rescue Exception => err
    ensure
      assert_kind_of CustomException, err
      assert_equal 'custom message', err.message
    end


    begin
      e = nil
      @timer.cancel_after(0.01, with_exception: 'foo') do
        sleep 1
        :foo
      end
    rescue => e
    ensure
      assert_kind_of RuntimeError, e
      assert_equal 'foo', e.message
    end
  end
end

class TimerMiscTest < MiniTest::Test
  def setup
    super
    @timer = Polyphony::Timer.new(resolution: 0.001)
    sleep 0
  end

  def teardown
    @timer.stop
    super
  end

  def test_timer_after
    buffer = []
    f = @timer.after(0.1) { buffer << 2 }
    assert_kind_of Fiber, f
    snooze
    assert_equal [], buffer
    sleep 0.2
    assert_equal [2], buffer
  end

  def test_timer_every
    buffer = []
    t0 = Time.now
    f = spin do
      @timer.every(0.01) { buffer << 1 }
    end
    sleep 0.05
    f.stop
    assert_in_range 3..7, buffer.size if IS_LINUX
  end
end
