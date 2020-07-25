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
end