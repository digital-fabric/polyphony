# frozen_string_literal: true

require_relative 'helper'

class TimerMoveOnAfterTest < MiniTest::Test
  def setup
    @timer = Polyphony::Timer.new(resolution: 0.01)
  end

  def teardown
    @timer.stop
  end

  def test_move_on_after
    t0 = Time.now
    v = @timer.move_on_after(0.1) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert_in_range 0.1..0.15, t1 - t0
    assert_nil v
  end

  def test_move_on_after_with_value
    t0 = Time.now
    v = @timer.move_on_after(0.01, with_value: :bar) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert_in_range 0.01..0.025, t1 - t0
    assert_equal :bar, v
  end

  def test_move_on_after_with_reset
    t0 = Time.now
    v = @timer.move_on_after(0.01, with_value: :moved_on) do
      sleep 0.007
      @timer.reset
      sleep 0.007
      @timer.reset
      sleep 0.007
      nil
    end
    t1 = Time.now

    assert_nil v
    assert_in_range 0.02..0.03, t1 - t0
  end
end

class TimerCancelAfterTest < MiniTest::Test
  def setup
    @timer = Polyphony::Timer.new(resolution: 0.01)
  end

  def teardown
    @timer.stop
  end

  def test_cancel_after
    t0 = Time.now

    assert_raises Polyphony::Cancel do
      @timer.cancel_after(0.01) do
        sleep 1
        :foo
      end
    end
    t1 = Time.now
    assert_in_range 0.01..0.02, t1 - t0
  end

  def test_cancel_after_with_reset
    t0 = Time.now
    @timer.cancel_after(0.01) do
      sleep 0.007
      @timer.reset
      sleep 0.007
    end
    t1 = Time.now
    assert_in_range 0.014..0.024, t1 - t0
  end

  class CustomException < Exception
  end

  def test_cancel_after_with_custom_exception
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
