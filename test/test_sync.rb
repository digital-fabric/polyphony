# frozen_string_literal: true

require_relative 'helper'

class MutexTest < MiniTest::Test
  def test_mutex
    buf = []
    lock = Polyphony::Mutex.new
    (1..3).each do |i|
      spin do
        lock.synchronize do
          buf << ">> #{i}"
          sleep(rand * 0.05)
          buf << "<< #{i}"
        end
      end
    end

    Fiber.current.await_all_children
    assert_equal ['>> 1', '<< 1', '>> 2', '<< 2', '>> 3', '<< 3'], buf
  end

  def test_mutex_race_condition
    lock = Polyphony::Mutex.new
    buf = []
    f1 = spin do
      lock.synchronize { buf << 1; snooze; lock.synchronize { buf << 1.1 }; snooze }
    end
    f2 = spin do
      lock.synchronize { buf << 2 }
    end
    f3 = spin do
      lock.synchronize { buf << 3 }
    end

    snooze
    f2.terminate

    f3.await

    assert_equal [1, 1.1, 3], buf
  end

  def test_condition_variable
    buf = []
    lock1 = Polyphony::Mutex.new
    lock2 = Polyphony::Mutex.new
    cond = Polyphony::ConditionVariable.new

    spin do
      lock1.synchronize do
        sleep 0.01
        cond.wait(lock1)
        lock2.synchronize do
          buf << :foo
        end
      end
    end

    spin do
      lock2.synchronize do
        sleep 0.01
        lock1.synchronize do
          buf << :bar
        end
        cond.signal
      end
    end

    Fiber.current.await_all_children
    assert_equal [:bar, :foo], buf
  end

  def test_owned?
    buf = []
    lock = Polyphony::Mutex.new
    (1..3).each do |i|
      spin do
        lock.synchronize do
          buf << ">> #{i}"
          buf << [i, lock.owned?]
          sleep(rand * 0.05)
          buf << "<< #{i}"
        end
        buf << [i, lock.owned?]
      end
    end

    Fiber.current.await_all_children
    assert_equal ['>> 1', [1, true], '<< 1', [1, false], '>> 2', [2, true], '<< 2', [2, false], '>> 3', [3, true], '<< 3', [3, false]], buf
  end

  def test_locked?
    lock = Polyphony::Mutex.new
    a = spin do
      sender = receive
      lock.synchronize do
        sender << 'pong'
        receive
      end
      sender << 'pong'
    end

    snooze
    assert !lock.locked?
    a << Fiber.current
    
    receive
    assert lock.locked?

    a << Fiber.current
    
    receive
    assert !lock.locked?
  end
end