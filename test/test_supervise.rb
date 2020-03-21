# frozen_string_literal: true

require_relative 'helper'

class SuperviseTest < MiniTest::Test
  def test_supervise
    p = spin { supervise }
    snooze
    f1 = p.spin { receive }
    f2 = p.spin { receive }

    snooze
    assert_equal p.state, :waiting
    f1 << 'foo'
    f1.await
    snooze

    assert_equal :waiting, p.state
    assert_equal :waiting, f2.state

    f2 << 'bar'
    f2.await
    snooze

    assert_equal :waiting, p.state
  end

  def test_supervise_with_restart
    parent = spin { supervise(on_error: :restart) }
    snooze

    buffer = []
    f1 = parent.spin do
      buffer << 'f1'
      buffer << receive
    end

    snooze
    assert_equal ['f1'], buffer

    f1.raise 'foo'

    3.times { snooze }

    assert_equal ['f1', 'f1'], buffer
    assert_equal :dead, f1.state

    # f1 should have been restarted by supervisor
    f1 = parent.children.first
    assert_kind_of Fiber, f1
    f1 << 'foo'

    f1.await
    3.times { snooze }

    assert_equal ['f1', 'f1', 'foo'], buffer
  end

  def test_supervise_with_block
    failed = []
    p = spin do
      supervise(on_error: :restart) { |f, e| failed << [f, e] }
    end
    snooze
    f1 = p.spin { receive }
    snooze

    f1.raise 'foo'
    3.times { snooze }

    assert_equal 1, failed.size
    assert_equal f1, failed.first[0]
    assert_kind_of RuntimeError, failed.first[1]
    assert_equal 'foo', failed.first[1].message
  end

  def test_supervisor_termination
    f = nil
    p = spin do
      f = spin { sleep 1 }
      supervise
    end
    sleep 0.01

    p.terminate
    p.await

    assert :dead, f.state
    assert :dead, p.state
  end

  def test_supervisor_termination_with_restart
    f = nil
    p = spin do
      f = spin { sleep 1 }
      supervise(on_error: :restart)
    end
    sleep 0.01

    p.terminate
    p.await

    assert :dead, f.state
    assert :dead, p.state
  end
end
