# Adapted from: https://github.com/ruby/ruby/blob/master/test/monitor/test_monitor.rb

# frozen_string_literal: true

require_relative 'helper'

class TestMonitor < MiniTest::Test
  Queue = Polyphony::Queue

  def setup
    super
    @monitor = Polyphony::Monitor.new
  end

  def test_enter_in_different_fibers
    @monitor.enter
    Fiber.new {
      assert_equal false, @monitor.try_enter
    }.resume
  end

  def test_enter
    ary = []
    queue = Thread::Queue.new
    f1 = spin {
      queue.pop
      @monitor.enter
      for i in 6 .. 10
        ary.push(i)
        snooze
      end
      @monitor.exit
    }
    f2 = spin {
      @monitor.enter
      queue.enq(nil)
      for i in 1 .. 5
        ary.push(i)
        snooze
      end
      @monitor.exit
    }
    Fiber.await(f1, f2)
    assert_equal((1..10).to_a, ary)
  end

  def test_exit
    m = Polyphony::Monitor.new
    m.enter
    assert_equal true, m.mon_owned?
    m.exit
    assert_equal false, m.mon_owned?

    assert_raises ThreadError do
      m.exit
    end

    assert_equal false, m.mon_owned?

    m.enter
    Thread.new{
      assert_raises ThreadError do
        m.exit
      end
      true
    }.join
    assert_equal true, m.mon_owned?
    m.exit
  end

  def test_enter_second_after_killed_thread
    th = Thread.new {
      @monitor.enter
      Thread.current.kill
      @monitor.exit
    }
    th.join
    @monitor.enter
    @monitor.exit
    th2 = Thread.new {
      @monitor.enter
      @monitor.exit
    }
    assert_join_threads([th, th2])
  end

  def test_synchronize
    ary = []
    f1 = spin {
      receive
      @monitor.synchronize do
        for i in 6 .. 10
          ary.push(i)
          snooze
        end
      end
    }
    f2 = spin {
      @monitor.synchronize do
        f1 << :continue
        for i in 1 .. 5
          ary.push(i)
          snooze
        end
      end
    }
    Fiber.await(f1, f2)
    assert_equal((1..10).to_a, ary)
  end

  def test_killed_thread_in_synchronize
    ary = []
    queue = Thread::Queue.new
    t1 = Thread.new {
      queue.pop
      @monitor.synchronize {
        ary << :t1
      }
    }
    t2 = Thread.new {
      queue.pop
      @monitor.synchronize {
        ary << :t2
      }
    }
    t3 = Thread.new {
      @monitor.synchronize do
        queue.enq(nil)
        queue.enq(nil)
        assert_equal([], ary)
        t1.kill
        t2.kill
        ary << :main
      end
      assert_equal([:main], ary)
    }
    assert_join_threads([t1, t2, t3])
  end

  def test_try_enter
    queue1 = Thread::Queue.new
    queue2 = Thread::Queue.new
    th = Thread.new {
      queue1.deq
      @monitor.enter
      queue2.enq(nil)
      queue1.deq
      @monitor.exit
      queue2.enq(nil)
    }
    th2 = Thread.new {
      assert_equal(true, @monitor.try_enter)
      @monitor.exit
      queue1.enq(nil)
      queue2.deq
      assert_equal(false, @monitor.try_enter)
      queue1.enq(nil)
      queue2.deq
      assert_equal(true, @monitor.try_enter)
    }
    assert_join_threads([th, th2])
  end

  def test_try_enter_second_after_killed_thread
    th = Thread.new {
      assert_equal(true, @monitor.try_enter)
      Thread.current.kill
      @monitor.exit
    }
    th.join
    assert_equal(true, @monitor.try_enter)
    @monitor.exit
    th2 = Thread.new {
      assert_equal(true, @monitor.try_enter)
      @monitor.exit
    }
    assert_join_threads([th, th2])
  end

  def test_mon_locked_and_owned
    queue1 = Thread::Queue.new
    queue2 = Thread::Queue.new
    th = Thread.new {
      @monitor.enter
      queue1.enq(nil)
      queue2.deq
      @monitor.exit
      queue1.enq(nil)
    }
    queue1.deq
    assert(@monitor.mon_locked?)
    assert(!@monitor.mon_owned?)

    queue2.enq(nil)
    queue1.deq
    assert(!@monitor.mon_locked?)

    @monitor.enter
    assert @monitor.mon_locked?
    assert @monitor.mon_owned?
    @monitor.exit

    @monitor.synchronize do
      assert @monitor.mon_locked?
      assert @monitor.mon_owned?
    end
  ensure
    th.join
  end

  def test_cond
    cond = @monitor.new_cond

    a = "foo"
    queue1 = Thread::Queue.new
    th = Thread.new do
      queue1.deq
      @monitor.synchronize do
        a = "bar"
        cond.signal
      end
    end
    th2 = Thread.new do
      @monitor.synchronize do
        queue1.enq(nil)
        assert_equal("foo", a)
        result1 = cond.wait
        assert_equal(true, result1)
        assert_equal("bar", a)
      end
    end
    assert_join_threads([th, th2])
  end

  class NewCondTest
    include ::MonitorMixin
    attr_reader :cond
    def initialize
      @cond = new_cond
      super # mon_initialize
    end
  end

  def test_new_cond_before_initialize
    assert NewCondTest.new.cond.instance_variable_get(:@monitor) != nil
  end

  class KeywordInitializeParent
    def initialize(x:)
    end
  end

  class KeywordInitializeChild < KeywordInitializeParent
    include ::MonitorMixin
    def initialize
      super(x: 1)
    end
  end

  def test_initialize_with_keyword_arg
    assert KeywordInitializeChild.new
  end

  def test_timedwait
    cond = @monitor.new_cond
    b = "foo"
    queue2 = Thread::Queue.new
    th = Thread.new do
      queue2.deq
      @monitor.synchronize do
        b = "bar"
        cond.signal
      end
    end
    result2 = nil
    @monitor.synchronize do
      queue2.enq(nil)
      assert_equal("foo", b)
      result2 = cond.wait(0.1)
      assert_equal(true, result2)
      assert_equal("bar", b)
    end
    th.join

    c = "foo"
    queue3 = Thread::Queue.new
    th = Thread.new do
      queue3.deq
      @monitor.synchronize do
        c = "bar"
        cond.signal
      end
    end
    th2 = Thread.new do
      @monitor.synchronize do
        assert_equal("foo", c)
        result3 = cond.wait(0.1)
        assert_equal(false, result3)
        assert_equal("foo", c)
        queue3.enq(nil)
        result4 = cond.wait
        assert_equal(true, result4)
        assert_equal("bar", c)
      end
    end
    assert_join_threads([th, th2])

#     d = "foo"
#     cumber_thread = Thread.new {
#       loop do
#         @monitor.synchronize do
#           d = "foo"
#         end
#       end
#     }
#     queue3 = Thread::Queue.new
#     Thread.new do
#       queue3.pop
#       @monitor.synchronize do
#         d = "bar"
#         cond.signal
#       end
#     end
#     @monitor.synchronize do
#       queue3.enq(nil)
#       assert_equal("foo", d)
#       result5 = cond.wait
#       assert_equal(true, result5)
#       # this thread has priority over cumber_thread
#       assert_equal("bar", d)
#     end
#     cumber_thread.kill
  end

  def test_wait_interruption
    cond = @monitor.new_cond

    th = Thread.new {
      @monitor.synchronize do
        begin
          cond.wait(0.1)
          @monitor.mon_owned?
        rescue Interrupt
          @monitor.mon_owned?
        end
      end
    }
    sleep(0.1)
    th.raise(Interrupt)

    begin
      assert_equal true, th.value
    rescue Interrupt
    end
  end
end
