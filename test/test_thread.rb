# frozen_string_literal: true

require_relative 'helper'
require 'polyphony/adapters/trace'

class ThreadTest < MiniTest::Test
  def test_thread_spin
    buffer = []
    f = spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new do
      sleep 0.01
      s1 = spin { (11..13).each { |i| snooze; buffer << i } }
      s2 = spin { (21..23).each { |i| snooze; buffer << i } }
      sleep 0.02
      Fiber.current.await_all_children
    end
    f.join
    t.join
    t = nil

    assert_equal [1, 2, 3, 11, 12, 13, 21, 22, 23], buffer.sort
  ensure
    t&.kill
    t&.join
  end

  def test_thread_join
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 0.01; buffer << 4; :foo }

    r = t.join
    t = nil

    assert_equal :foo, r
    assert_equal [1, 2, 3, 4], buffer
  ensure
    t&.kill
    t&.join
  end

  def test_thread_join_with_timeout
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 1; buffer << 4 }
    t0 = Time.now
    r = t.join(0.01)
    t = nil

    assert Time.now - t0 < 0.2
    assert_equal [1, 2, 3], buffer
    assert_nil r
  ensure
    # killing the thread will prevent stopping the sleep timer, as well as the
    # thread's event selector, leading to a memory leak.
    t&.kill
    t&.join
  end

  def test_thread_await_alias_method
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 0.01; buffer << 4; :foo }
    r = t.await
    t = nil

    assert_equal [1, 2, 3, 4], buffer
    assert_equal :foo, r
  ensure
    t&.kill
    t&.join
  end

  def test_join_race_condition_on_thread_spawning
    buffer = []
    t = Thread.new do
      :foo
    end
    r = t.join
    t = nil
    assert_equal :foo, r
  ensure
    t&.kill
    t&.join
  end

  def test_thread_uncaught_exception_propagation
    ready = Polyphony::Event.new

    t = Thread.new do
      ready.signal
      sleep 0.01
      raise 'foo'
    end
    e = nil
    begin
      ready.await
      r = t.await
    rescue Exception => e
    end
    t = nil
    assert_kind_of RuntimeError, e
    assert_equal 'foo', e.message
  ensure
    t&.kill
    t&.join
  end

  def test_thread_inspect
    lineno = __LINE__ + 1
    t = Thread.new { sleep 1 }
    str = format(
      "#<Thread:%d %s:%d",
      t.object_id,
      __FILE__,
      lineno,
    )
    assert t.inspect =~ /#{str}/
  rescue => e
    p e
    puts e.backtrace.join("\n")
  ensure
    t&.kill
    t&.join
  end

  def test_backend_class_method
    assert_equal Thread.current.backend, Thread.backend
  end

  def test_that_suspend_returns_immediately_if_no_watchers
    records = []
    t = Polyphony::Trace.new(:fiber_all) do |r|
      records << r if r[:event] =~ /^fiber_/
    end
    t.enable
    Polyphony.trace(true)

    suspend
    t.disable
    assert_equal [:fiber_switchpoint], records.map { |r| r[:event] }
  ensure
    t&.disable
    Polyphony.trace(false)
  end

  def test_thread_child_fiber_termination
    buffer = []
    t = Thread.new do
      spin do
        sleep 61
      ensure
        buffer << :foo
      end
      spin do
        sleep 62
      ensure
        buffer << :bar
      end
      assert 2, Fiber.current.children.size
      sleep 1
    end
    sleep 0.05
    assert_equal 2, t.main_fiber.children.size
    t.kill
    t.join
    t = nil

    assert_equal [:foo, :bar], buffer
  ensure
    t&.kill
    t&.join
  end
end
