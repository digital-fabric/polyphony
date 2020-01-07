# frozen_string_literal: true

require_relative 'helper'

class CancelScopeTest < MiniTest::Test
  def test_that_cancel_scope_can_cancel_provided_block
    buffer = []
    Polyphony::CancelScope.new { |scope|
      defer { scope.cancel! }
      buffer << 1
      snooze
      buffer << 2
    }
    assert_equal [1], buffer
  end

  def test_that_cancel_scope_can_cancel_multiple_coprocesses
    buffer = []
    scope = Polyphony::CancelScope.new
    coprocs = (1..3).map { |i|
      spin {
        scope.call do
          buffer << i
          snooze
          buffer << i * 10
        end
      }
    }
    snooze
    scope.cancel!
    assert_equal [1, 2, 3], buffer
  end

  def test_that_cancel_scope_takes_timeout_option
    buffer = []
    Polyphony::CancelScope.new(timeout: 0.01) { |scope|
      buffer << 1
      sleep 0.02
      buffer << 2
    }
    assert_equal [1], buffer
  end

  def test_that_cancel_scope_cancels_timeout_waiter_if_block_provided
    buffer = []
    t0 = Time.now
    scope = Polyphony::CancelScope.new(timeout: 1) { |scope|
      buffer << 1
    }
    assert_equal [1], buffer
    assert Time.now - t0 < 1
    assert_nil scope.instance_variable_get(:@timeout_waiter)
  end

  def test_that_cancel_scope_can_cancel_multiple_coprocs_with_timeout
    buffer = []
    t0 = Time.now
    scope = Polyphony::CancelScope.new(timeout: 0.02)
    coprocs = (1..3).map { |i|
      spin {
        scope.call do
          buffer << i
          sleep i
          buffer << i * 10
        end
      }
    }
    Polyphony::Coprocess.await(*coprocs)
    assert Time.now - t0 < 0.05
    assert_equal [1, 2, 3], buffer
  end

  def test_reset_timeout
    buffer = []
    scope = Polyphony::CancelScope.new(timeout: 0.01)
    t0 = Time.now
    scope.call {
      sleep 0.005
      scope.reset_timeout
      sleep 0.010
    }

    assert !scope.cancelled?
  end

  def test_on_cancel
    buffer = []
    Polyphony::CancelScope.new { |scope|
      defer { scope.cancel! }
      scope.on_cancel { buffer << :cancelled }
      buffer << 1
      snooze
      buffer << 2
    }
    assert_equal [1, :cancelled], buffer
  end

  def test_cancelled?
    scope = Polyphony::CancelScope.new
    spin {
      scope.call { sleep 1 }
    }

    snooze
    assert !scope.cancelled?
    scope.cancel!
    assert scope.cancelled?
  end
end