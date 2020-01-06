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

  def test_await_multiple_coprocs
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

  def test_join_multiple_coprocs
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

    assert_equal [Polyphony::Coprocess], buffer.map { |v| v.class }.uniq
  end

  def test_select
    buffer = []
    foo_cp = bar_cp = baz_cp = nil
    result, cp = Polyphony::Supervisor.new.select { |s|
      foo_cp = s.spin { sleep 0.01; buffer << :foo; :foo }
      bar_cp = s.spin { sleep 0.02; buffer << :bar; :bar }
      baz_cp = s.spin { sleep 0.03; buffer << :baz; :baz }
    }

    assert_equal :foo, result
    assert_equal foo_cp, cp

    sleep 0.03
    assert_nil bar_cp.alive?
    assert_nil baz_cp.alive?
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

  def test_add
    supervisor = Polyphony::Supervisor.new
    supervisor << spin { :foo }
    supervisor << spin { :bar }

    assert_equal [:foo, :bar], supervisor.await
  end
end

class CoprocessExtensionsTest < MiniTest::Test
  def test_join
    cp1 = spin { :foo }
    cp2 = spin { :bar }
    assert_equal [:foo, :bar], Polyphony::Coprocess.join(cp1, cp2)

    cp1 = spin { :foo }
    cp2 = spin { raise 'bar' }
    result = capture_exception { Polyphony::Coprocess.join(cp1, cp2) }
    assert_kind_of RuntimeError, result
    assert_equal 'bar', result.message
  end

  def test_select
    cp1 = spin { sleep 1; :foo }
    cp2 = spin { :bar }
    assert_equal [:bar, cp2], Polyphony::Coprocess.select(cp1, cp2)

    cp1 = spin { :foo }
    cp2 = spin { sleep 0.01; raise 'bar' }
    assert_equal [:foo, cp1], Polyphony::Coprocess.select(cp1, cp2)

    cp1 = spin { sleep 1; :foo }
    cp2 = spin { raise 'bar' }
    result = capture_exception { Polyphony::Coprocess.select(cp1, cp2) }
    assert_kind_of RuntimeError, result
    assert_equal 'bar', result.message
  end
end