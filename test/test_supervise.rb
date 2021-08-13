# frozen_string_literal: true

require_relative 'helper'

class SuperviseTest < MiniTest::Test
  def test_supervise_with_no_arguments
    assert_raises(RuntimeError) do
      supervise
    end
  end
  
  def test_supervise_with_block
    buffer = []
    f1 = spin(:f1) { receive }
    f2 = spin(:f2) { receive }
    supervisor = spin(:supervisor) { supervise(f1, f2) { |*args| buffer << args } }

    snooze
    f1 << 'foo'
    f1.await
    10.times { snooze }
    assert_equal [[f1, 'foo']], buffer

    f2 << 'bar'
    f2.await
    assert_equal [[f1, 'foo'], [f2, 'bar']], buffer
  end

  def test_supervise_with_on_done
    buffer = []
    f1 = spin(:f1) { receive }
    f2 = spin(:f2) { receive }
    supervisor = spin(:supervisor) do
      supervise(f1, f2, on_done: ->(*args) { buffer << args })
    end

    snooze
    f1 << 'foo'
    f1.await
    10.times { snooze }
    assert_equal [[f1, 'foo']], buffer

    f2 << 'bar'
    f2.await
    assert_equal [[f1, 'foo'], [f2, 'bar']], buffer
  end

  def test_supervise_with_on_error
    buffer = []
    f1 = spin(:f1) { receive }
    f2 = spin(:f2) { receive }
    supervisor = spin(:supervisor) do
      supervise(f1, f2, on_error: ->(*args) { buffer << args })
    end

    snooze
    f1 << 'foo'
    f1.await
    10.times { snooze }
    assert_equal [], buffer

    e = RuntimeError.new('blah')
    f2.raise(e)
    3.times { snooze }
    assert_equal [[f2, e]], buffer
  end

  def test_supervise_with_manual_restart
    buffer = []
    f1 = spin(:f1) { receive }
    supervisor = spin(:supervisor) do
      supervise(f1) do |f, r|
        buffer << [f, r]
        f.restart
      end
    end

    snooze
    f1 << 'foo'
    f1.await
    snooze
    assert_equal [[f1, 'foo']], buffer

    10.times { snooze }

    assert_equal 1, supervisor.children.size
    f2 = supervisor.children.first
    assert f1 != f2
    assert_equal :f1, f2.tag
    assert_equal supervisor, f2.parent

    e = RuntimeError.new('bar')
    f2.raise(e)
    f2.await rescue nil
    3.times { snooze }
    assert_equal [[f1, 'foo'], [f2, e]], buffer

    assert_equal 1, supervisor.children.size
    f3 = supervisor.children.first
    assert f2 != f3
    assert f1 != f3
    assert_equal :f1, f3.tag
    assert_equal supervisor, f3.parent
  end

#   def test_supervise_with_restart
#     watcher = spin { receive }
#     parent = spin { supervise(restart: true, watcher: watcher) }
#     snooze

#     buffer = []
#     f1 = parent.spin do
#       buffer << 'f1'
#     end

#     f1.await
#     assert_equal ['f1'], buffer
#     watcher.await
#     assert_equal ['f1', 'f1'], buffer
#   end

#   def test_supervise_with_restart_on_error
#     parent = spin { supervise(restart: true) }
#     snooze

#     buffer = []
#     f1 = parent.spin do
#       buffer << 'f1'
#       buffer << receive
#     end

#     snooze
#     assert_equal ['f1'], buffer

#     f1.raise 'foo'

#     3.times { snooze }

#     assert_equal ['f1', 'f1'], buffer
#     assert_equal :dead, f1.state

#     # f1 should have been restarted by supervisor
#     f1 = parent.children.first
#     assert_kind_of Fiber, f1

#     f1 << 'foo'
#     f1.await

#     assert_equal ['f1', 'f1', 'foo'], buffer
#   end

#   def test_supervisor_termination
#     f = nil
#     p = spin do
#       f = spin { sleep 1 }
#       supervise
#     end
#     sleep 0.01

#     p.terminate
#     p.await

#     assert :dead, f.state
#     assert :dead, p.state
#   end

#   def test_supervisor_termination_with_restart
#     f = nil
#     p = spin do
#       f = spin { sleep 1 }
#       supervise(restart: true)
#     end
#     sleep 0.01

#     p.terminate
#     p.await

#     assert :dead, f.state
#     assert :dead, p.state
#   end
end
