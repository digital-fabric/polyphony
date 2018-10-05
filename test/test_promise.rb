require 'minitest/autorun'
require 'modulation'

class PromiseTest < Minitest::Test
  # 
  Core = import('../lib/nuclear/core')

  def test_that_promise_resolves
    p = Core.promise
    result = nil
    p.then { |v| result = v }.catch { |e| result = e }
    assert_nil(result)
    p.resolve(42)
    assert_equal(42, result)
  end

  def test_that_promise_catches_error
    p = Core.promise
    result = nil
    p.then { |v| result = v }.catch { |e| result = e }
    assert_nil(result)
    p.reject(RuntimeError.new('hi'))
    assert_kind_of(RuntimeError, result)
    assert_equal('hi', result.message)
  end

  def setup_ops
    log = []
    promises = 3.times.map { Core.promise }
    ops = promises.map { |p| ->(v) { log << v; p} }

    [promises, ops, log]
  end

  def start_ops(ops, log)
    ops[0].(1).
      then  { |v| ops[1].(v * 2) }.
      then  { |v| ops[2].(v * 3) }.
      then  { |v| log << v * 4 }.
      catch { |e| log << e }
  end

  def resolve_promises(promises, log, error_idx = nil)
    promises.each_with_index do |p, idx|
      if idx == error_idx
        return p.reject(RuntimeError.new("idx:#{error_idx}"))
      else
        p.resolve(log.last)
      end
    end
  end

  def test_that_promise_can_be_chained
    promises, ops, log = setup_ops
    start_ops(ops, log)
    resolve_promises(promises, log)
    assert_equal [1, 2, 6, 24], log
  end

  def test_that_error_is_passed_down_chain
    promises, ops, log = setup_ops
    start_ops(ops, log)
    resolve_promises(promises, log, 0)
    assert_equal 2, log.size
    assert_equal 1, log[0]
    assert_kind_of RuntimeError, log[1]
    assert_equal 'idx:0', log[1].message

    promises, ops, log = setup_ops
    start_ops(ops, log)
    resolve_promises(promises, log, 1)
    assert_equal 3, log.size
    assert_equal [1, 2], log[0..1]
    assert_kind_of RuntimeError, log[2]
    assert_equal 'idx:1', log[2].message

    promises, ops, log = setup_ops
    start_ops(ops, log)
    resolve_promises(promises, log, 2)
    assert_equal 4, log.size
    assert_equal [1, 2, 6], log[0..2]
    assert_kind_of RuntimeError, log[3]
    assert_equal 'idx:2', log[3].message
  end

  def start_ops_with_error_boundary(ops, log)
    ops[0].(1).
    then  { |v| ops[1].(v * 2) }.
    catch { |e| log << { err: e } }.
    then  { |v| ops[2].(v * 3) }.
    then  { |v| log << v * 4 }.
    catch { |e| log << e }
  end

  def test_that_error_boundary_is_respected_in_chain
    promises, ops, log = setup_ops
    start_ops_with_error_boundary(ops, log)
    resolve_promises(promises, log, 0)
    assert_equal 2, log.size
    assert_equal 1, log[0]
    assert_kind_of Hash, log[1]
    assert_kind_of RuntimeError, log[1][:err]
    assert_equal 'idx:0', log[1][:err].message

    promises, ops, log = setup_ops
    start_ops_with_error_boundary(ops, log)
    resolve_promises(promises, log, 1)
    assert_equal 3, log.size
    assert_equal [1, 2], log[0..1]
    assert_kind_of Hash, log[2]
    assert_kind_of RuntimeError, log[2][:err]
    assert_equal 'idx:1', log[2][:err].message

    promises, ops, log = setup_ops
    start_ops_with_error_boundary(ops, log)
    resolve_promises(promises, log, 2)
    assert_equal 4, log.size
    assert_equal [1, 2, 6], log[0..2]
    assert_kind_of RuntimeError, log[3]
    assert_equal 'idx:2', log[3].message
  end
end
