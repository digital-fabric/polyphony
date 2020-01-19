# frozen_string_literal: true

require_relative 'helper'

class SupervisorTest < MiniTest::Test
  def test_await
    result = Polyphony::Supervisor.new.await { |s|
      s.spin {
        snooze
        :foo
      }
    }
    assert_equal [:foo], result
  end

  def test_await_multiple_fibers
    result = Polyphony::Supervisor.new.await { |s|
      (1..3).each { |i|
        s.spin {
          snooze
          i * 10
        }
      }
    }
    assert_equal [10, 20, 30], result
  end

  def test_join_multiple_fibers
    result = Polyphony::Supervisor.new.join { |s|
      (1..3).each { |i|
        s.spin {
          snooze
          i * 10
        }
      }
    }
    assert_equal [10, 20, 30], result
  end

  def test_spin_method
    buffer = []
    Polyphony::Supervisor.new.join { |s|
      (1..3).each { |i|
        buffer << s.spin {
          snooze
          i * 10
        }
      }
    }

    assert_equal [Fiber], buffer.map { |v| v.class }.uniq
  end

  def test_supervisor_select
    buffer = []
    foo_f = bar_f = baz_f = nil
    result, f = Polyphony::Supervisor.new.select { |s|
      foo_f = s.spin { sleep 0.1; buffer << :foo; :foo }
      bar_f = s.spin { sleep 0.3; buffer << :bar; :bar }
      baz_f = s.spin { sleep 0.5; buffer << :baz; :baz }
    }

    assert_equal :foo, result
    assert_equal foo_f, f

    sleep 0.05
    assert !bar_f.running?
    assert !baz_f.running?
    assert_equal [:foo], buffer
  end

  def test_await_with_exception
    buffer = []
    result = capture_exception do
      Polyphony::Supervisor.new.await { |s|
        (1..3).each { |i|
          s.spin {
            raise 'foo' if i == 1
            snooze
            buffer << i * 10
            i * 10
          }
        }
      }
    end

    assert_kind_of RuntimeError, result
    assert_equal 'foo', result.message
    snooze
    assert_equal [], buffer
  end

  def test_await_interruption
    buffer = []
    supervisor = nil
    supervisor = Polyphony::Supervisor.new
    defer { supervisor.interrupt(42) }
    buffer << supervisor.await { |s|
      (1..3).each { |i|
        s.spin {
          buffer << i
          sleep i
          buffer << i * 10
        }
      }
    }

    snooze
    assert_equal [1, 2, 3, 42], buffer
  end

  def test_select_interruption
    buffer = []
    supervisor = nil
    supervisor = Polyphony::Supervisor.new
    defer { supervisor.interrupt(42) }
    buffer << supervisor.select { |s|
      (1..3).each { |i|
        s.spin {
          buffer << i
          sleep i
          buffer << i * 10
        }
      }
    }

    snooze
    assert_equal [1, 2, 3, 42], buffer
  end

  def test_add
    supervisor = Polyphony::Supervisor.new
    supervisor << spin { :foo }
    supervisor << spin { :bar }

    assert_equal [:foo, :bar], supervisor.await
  end
end

class FiberExtensionsTest < MiniTest::Test
  def test_join
    f1 = spin { :foo }
    f2 = spin { :bar }
    assert_equal [:foo, :bar], Fiber.join(f1, f2)

    f1 = spin { :foo }
    f2 = spin { raise 'bar' }
    result = capture_exception { Fiber.join(f1, f2) }
    assert_kind_of RuntimeError, result
    assert_equal 'bar', result.message
  end

  def test_select
    f1 = spin { sleep 1; :foo }
    f2 = spin { :bar }
    assert_equal [:bar, f2], Fiber.select(f1, f2)

    f1 = spin { :foo }
    f2 = spin { sleep 0.01; raise 'bar' }
    assert_equal [:foo, f1], Fiber.select(f1, f2)

    f1 = spin { sleep 1; :foo }
    f2 = spin { raise 'bar' }
    result = capture_exception { Fiber.select(f1, f2) }
    assert_kind_of RuntimeError, result
    assert_equal 'bar', result.message
  end
end