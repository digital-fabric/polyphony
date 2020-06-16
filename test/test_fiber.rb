# frozen_string_literal: true

require_relative 'helper'

class FiberTest < MiniTest::Test
  def test_spin_initial_state
    result = nil
    f = Fiber.current.spin { result = 42 }
    assert_nil result
    f.await
    assert_equal 42, result
  ensure
    f&.stop
  end

  def test_children_parent
    assert_nil Fiber.current.parent

    f1 = spin {}
    f2 = spin {}

    assert_equal [f1, f2], Fiber.current.children
    assert_equal Fiber.current, f1.parent
    assert_equal Fiber.current, f2.parent
  end

  def test_spin_from_different_fiber
    f1 = spin { sleep }
    f2 = f1.spin { sleep }
    assert_equal f1, f2.parent
    assert_equal [f2], f1.children
  end

  def test_await
    result = nil
    f = Fiber.current.spin do
      snooze
      result = 42
    end
    f.await
    assert_equal 42, result
  ensure
    f&.stop
  end

  def test_await_from_multiple_fibers
    buffer = []
    f1 = spin {
      sleep 0.02
      buffer << :foo
    }
    f2 = spin {
      f1.await
      buffer << :bar
    }
    f3 = spin {
      f1.await
      buffer << :baz
    }
    Fiber.await(f2, f3)
    assert_equal [:foo, :bar, :baz], buffer
    assert_equal 0, Fiber.current.children.size
  end

  def test_await_from_multiple_fibers_with_interruption
    buffer = []
    f1 = spin {
      sleep 0.02
      buffer << :foo
    }
    f2 = spin {
      f1.await
      buffer << :bar
    }
    f3 = spin {
      f1.await
      buffer << :baz
    }
    snooze
    f2.stop
    f3.stop
    snooze
    f1.stop

    snooze
    assert_equal [], Fiber.current.children
  end

  def test_schedule
    values = []
    fibers = (0..2).map { |i| spin { suspend; values << i } }
    snooze

    fibers[0].schedule
    assert_equal [], values

    snooze

    assert_equal [0], values
    assert_equal :dead, fibers[0].state

    fibers[1].schedule
    fibers[2].schedule

    assert_equal [0], values
    snooze
    assert_equal [0, 1, 2], values
  end

  def test_cross_thread_schedule
    buffer = []
    worker_fiber = nil
    async = Polyphony::Event.new
    worker = Thread.new do
      worker_fiber = Fiber.current
      async.signal
      suspend
      buffer << :foo
    end

    async.await
    assert worker_fiber
    worker_fiber.schedule
    worker.join
    assert_equal [:foo], buffer
  ensure
    worker&.kill
    worker&.join
  end

  def test_ev_loop_anti_starve_mechanism
    async = Polyphony::Event.new
    t = Thread.new do
      f = spin_loop { snooze }
      sleep 0.001
      async.signal(:foo)
    end

    result = move_on_after(1) { async.await }

    assert_equal :foo, result
  ensure
    t&.kill
    t&.join
  end

  def test_tag
    assert_equal :main, Fiber.current.tag
    Fiber.current.tag = :foo
    assert_equal :foo, Fiber.current.tag

    f = Fiber.current.spin(:bar) { }
    assert_equal :bar, f.tag
  end

  def test_await_return_value
    f = Fiber.current.spin { %i[foo bar] }
    assert_equal %i[foo bar], f.await
  ensure
    f&.stop
  end

  def test_await_with_error
    result = nil
    f = Fiber.current.spin { raise 'foo' }
    begin
      result = f.await
    rescue Exception => e
      result = { error: e }
    end
    assert_kind_of Hash, result
    assert_kind_of RuntimeError, result[:error]
    assert_equal f, result[:error].source_fiber
  ensure
    f&.stop
  end

  def test_raise
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    f2 = spin { f.raise }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of RuntimeError, error
    assert_equal f, error.source_fiber
  ensure
    f&.stop
  end

  class MyError < RuntimeError
  end

  def test_raise_with_error_class
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    spin { f.raise MyError }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
  ensure
    f&.stop
  end

  def test_raise_with_error_class_and_message
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    spin { f.raise(MyError, 'foo') }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
    assert_equal 'foo', error.message
  ensure
    f&.stop
  end

  def test_raise_with_message
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    f2 = spin { f.raise 'foo' }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of RuntimeError, error
    assert_equal 'foo', error.message
    assert_equal f, error.source_fiber
  ensure
    f&.stop
  end

  def test_raise_with_exception
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    spin { f.raise MyError.new('bar') }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
    assert_equal 'bar', error.message
  ensure
    f&.stop
  end

  def test_cancel
    result = []
    error = nil
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    spin { f.cancel }
    assert_equal 0, result.size
    begin
      f.await
    rescue Polyphony::Cancel => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of Polyphony::Cancel, error
  ensure
    f&.stop
  end

  def test_interrupt
    # that is, stopped without exception
    result = []
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
      3
    end
    spin { f.interrupt(42) }

    await_result = f.await
    assert_equal 1, result.size
    assert_equal 42, await_result
  ensure
    f&.stop
  end

  def test_terminate
    buffer = []
    f = spin do
      buffer << :foo
      sleep 1
      buffer << :bar
    rescue Polyphony::Terminate
      buffer << :terminate
    end
    snooze
    f.terminate
    snooze
    assert_equal [:foo, :terminate], buffer
  end

  def test_interrupt_timer
    result = []
    f = Fiber.current.spin do
      result << :start
      result << Thread.current.agent.sleep(1)
    end
    snooze
    f.interrupt
    f.join

    assert_equal [:start], result
  end

  def test_stop
    # that is, stopped without exception
    result = []
    f = Fiber.current.spin do
      result << 1
      2.times { snooze }
      result << 2
      3
    end
    spin { f.stop(42) }

    await_result = f.await
    assert_equal 1, result.size
    assert_equal 42, await_result
  ensure
    f&.stop
  end

  def test_interrupt_before_start
    result = []
    f = Fiber.current.spin do
      result << 1
    end
    f.interrupt(42)
    snooze

    assert_equal :dead, f.state
    assert_equal [], result
    assert_equal 42, f.result
  end

  def test_interrupt_nested_fiber
    result = nil
    f2 = nil
    f1 = spin do
      f2 = spin do
        snooze
        result = 42
      end
      f2.await
      result && result += 1
    end
    spin { f2.interrupt }
    suspend
    assert_nil result
    assert_equal :dead, f1.state
    assert_equal :dead, f2.state
  ensure
    f1&.stop
    f2&.stop
  end

  def test_state
    counter = 0
    f = spin do
      3.times do
        snooze
        counter += 1
      end
      suspend
    end

    assert_equal :runnable, f.state
    assert_equal :running, Fiber.current.state
    snooze
    assert_equal :runnable, f.state
    snooze while counter < 3
    assert_equal :waiting, f.state
    f.stop
    snooze
    assert_equal :dead, f.state
  ensure
    f&.stop
  end

  def test_main?
    f = spin {
      sleep
    }
    assert_nil f.main?
    assert_equal true, Fiber.current.main?
  end

  def test_exception_propagation
    # error is propagated to calling fiber
    raised_error = nil
    spin do
      spin do
        raise 'foo'
      end
      snooze # allow nested fiber to run before finishing
    end
    suspend
  rescue Exception => e
    raised_error = e
  ensure
    assert raised_error
    assert_equal 'foo', raised_error.message
  end

  def test_await_multiple_fibers
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 0.01; :bar }
    f3 = spin { sleep 0.01; :baz }

    result = Fiber.await(f1, f2, f3)
    assert_equal %i{foo bar baz}, result
  end

  def test_join_multiple_fibers
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 0.01; :bar }
    f3 = spin { sleep 0.01; :baz }

    result = Fiber.join(f1, f2, f3)
    assert_equal %i{foo bar baz}, result
  end

  def test_select_from_multiple_fibers
    sleep 0
    buffer = []
    f1 = spin { sleep 0.01; buffer << :foo; :foo }
    f2 = spin { sleep 0.03; buffer << :bar; :bar }
    f3 = spin { sleep 0.05; buffer << :baz; :baz }

    selected, result = Fiber.select(f1, f2, f3)
    assert_equal :foo, result
    assert_equal f1, selected
    assert_equal [:foo], buffer
  end

  def test_caller
    location = /^#{__FILE__}:#{__LINE__ + 1}/
    f = spin do
      sleep 0.01
    end
    snooze

    caller = f.caller
    assert_match location, caller[0]
  end

  def test_location
    location = /^#{__FILE__}:#{__LINE__ + 1}/
    f = spin do
      sleep 0.01
    end
    snooze

    assert f.location =~ location
  end

  def test_when_done
    flag = nil
    values = []
    f = spin do
      snooze until flag
    end
    f.when_done { values << 42 }

    snooze
    assert values.empty?
    snooze
    flag = true
    assert values.empty?
    assert f.alive?

    snooze
    assert_equal [42], values
    assert !f.running?
  end

  def test_children
    assert_equal [], Fiber.current.children

    f = spin { sleep 1 }
    snooze
    assert_equal [f], Fiber.current.children

    f.stop
    snooze
    assert_equal [], Fiber.current.children
  end

  def test_inspect
    expected = format('#<Fiber:%s (root) (running)>', Fiber.current.object_id)
    assert_equal expected, Fiber.current.inspect

    spin_line_no = __LINE__ + 1
    f = spin { :foo }

    expected = format(
      '#<Fiber:%s %s:%d:in `test_inspect\' (runnable)>',
      f.object_id,
      __FILE__,
      spin_line_no
    )
    assert_equal expected, f.inspect

    f.await
    expected = format(
      '#<Fiber:%s %s:%d:in `test_inspect\' (dead)>',
      f.object_id,
      __FILE__,
      spin_line_no
    )
    assert_equal expected, f.inspect
  end

  def test_system_exit_in_fiber
    error = nil
    spin do
      spin { raise SystemExit }.await
    end

    begin
      suspend
    rescue Exception => error
    end

    assert_kind_of SystemExit, error
  end

  def test_interrupt_in_fiber
    error = nil
    spin do
      spin { raise Interrupt }.await
    end

    begin
      suspend
    rescue Exception => error
    end

    assert_kind_of Interrupt, error
  end

  def test_signal_exception_in_fiber
    error = nil
    spin do
      spin { raise SignalException.new('HUP') }.await
    end

    begin
      suspend
    rescue Exception => error
    end

    assert_kind_of SignalException, error
  end

  def test_signal_handling_int
    i, o = IO.pipe
    pid = Polyphony.fork do
      f = spin { sleep 100 }
      begin
        i.close
        f.await
      rescue Exception => e
        o << e.class.name
        o.close
      end
    end
    sleep 0.1
    f = spin { Thread.current.agent.waitpid(pid) }
    o.close
    Process.kill('INT', pid)
    f.await
    klass = i.read
    i.close
    assert_equal 'Interrupt', klass
  end

  def test_signal_handling_term
    i, o = IO.pipe
    pid = Polyphony.fork do
      f = spin { sleep 100 }
      begin
        i.close
        f.await
      rescue Exception => e
        o << e.class.name
        o.close
      end
    end
    sleep 0.2
    f = spin { Thread.current.agent.waitpid(pid) }
    o.close
    Process.kill('TERM', pid)
    f.await
    klass = i.read
    o.close
    assert_equal 'SystemExit', klass
  end

  def test_main_fiber_child_termination_after_fork
    i, o = IO.pipe
    pid = Polyphony.fork do
      i.close
      spin do
        sleep 100
      rescue Exception => e
        o << e.class.to_s
        o.close
        raise e
      end
      suspend
    end
    o.close
    spin do
      sleep 0.2
      Process.kill('TERM', pid)
    end
    Thread.current.agent.waitpid(pid)
    klass = i.read
    i.close
    assert_equal 'Polyphony::Terminate', klass
  end

  def test_setup_raw
    buffer = []
    f = Fiber.new { buffer << receive }
    
    assert_raises(NoMethodError) { f << 'foo' }
    snooze
    f.setup_raw
    assert_equal Thread.current, f.thread
    assert_nil f.parent

    f.schedule
    f << 'bar'
    snooze
    assert_equal ['bar'], buffer
  end
end

class MailboxTest < MiniTest::Test
  def test_that_fiber_can_receive_messages
    msgs = []
    f = spin { loop { msgs << receive } }

    snooze # allow fiber to start

    3.times do |i|
      f << i
      sleep 0
    end
    sleep 0

    assert_equal [0, 1, 2], msgs
  ensure
    f&.stop
  end

  def test_that_multiple_messages_sent_at_once_arrive_in_order
    msgs = []
    f = spin { loop { msgs << receive } }

    snooze # allow coproc to start

    3.times { |i| f << i }

    sleep 0.01

    assert_equal [0, 1, 2], msgs
  ensure
    f&.stop
  end

  def test_that_sent_message_are_queued_before_calling_receive
    buffer = []
    receiver = spin { suspend; 3.times { buffer << receive } }
    sender = spin { 3.times { |i| receiver << (i * 10) } }

    sender.await
    receiver.schedule
    receiver.await

    assert_equal [0, 10, 20], buffer
  end

  def test_cross_thread_send_receive
    ping_receive_buffer = []
    pong_receive_buffer = []
    pong = Thread.new do
      sleep 0.05
      loop do
        peer, data = receive
        pong_receive_buffer << data
        peer << 'pong'
      end
    end

    ping = Thread.new do
      sleep 0.05
      3.times do
        pong << [Fiber.current, 'ping']
        data = receive
        ping_receive_buffer << data
      end
    end

    ping.join
    pong.kill

    assert_equal %w{pong pong pong}, ping_receive_buffer
    assert_equal %w{ping ping ping}, pong_receive_buffer
  ensure
    pong&.kill
    ping&.kill
    pong&.join
    ping&.join
  end

  def test_message_queueing
    messages = []
    f = spin do
      loop {
        msg = receive
        break if msg == 'stop'

        messages << msg
      }
    end

    100.times { f << 'foo' }
    f << 'stop'

    f.await
    assert_equal ['foo'] * 100, messages
  end

  def test_receive_pending
    assert_equal [], receive_pending

    (1..5).each { |i| Fiber.current << i }
    assert_equal (1..5).to_a, receive_pending
    assert_equal [], receive_pending
  end

  def test_receive_pending_on_termination
    buffer = []
    worker = spin do
      loop { buffer << receive }
    rescue Polyphony::Terminate
      receive_pending.each { |r| buffer << r }
    end

    worker << 1
    worker << 2
    10.times { snooze }
    assert_equal [1, 2], buffer

    worker << 3
    worker << 4
    worker << 5
    worker.terminate
    worker.await

    assert_equal (1..5).to_a, buffer
  end
end

class FiberControlTest < MiniTest::Test
  def test_await_multiple
    f1 = spin {
      snooze
      :foo
    }
    f2 = spin {
      snooze
      :bar
    }
    result = Fiber.await(f1, f2)
    assert_equal [:foo, :bar], result
  end

  def test_await_multiple_with_raised_error
    f1 = spin {
      snooze
      raise 'foo'
    }
    f2 = spin {
      snooze
      :bar
    }
    f3 = spin {
      sleep 3
    }
    error = nil
    begin
      Fiber.await(f1, f2, f3)
    rescue => error
    end
    assert_kind_of RuntimeError, error
    assert_equal 'foo', error.message
    assert_equal f1, error.source_fiber

    assert_equal :dead, f1.state
    assert_equal :dead, f2.state
    assert_equal :dead, f3.state
  end

  def test_await_multiple_with_interruption
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 1; :bar }
    spin { snooze; f2.interrupt(:baz) }
    result = Fiber.await(f1, f2)
    assert_equal [:foo, :baz], result
  end

  def test_select
    buffer = []
    f1 = spin { snooze; buffer << :foo; :foo }
    f2 = spin { :bar }
    result = Fiber.select(f1, f2)
    assert_equal [f2, :bar], result
    assert_equal [:foo], buffer
    assert_equal :dead, f1.state
  end

  def test_select_with_raised_error
    f1 = spin { snooze; raise 'foo' }
    f2 = spin { sleep 3 }

    result = nil
    begin
      result = Fiber.select(f1, f2)
    rescue => result
    end

    assert_kind_of RuntimeError, result
    assert_equal 'foo', result.message
    assert_equal f1, result.source_fiber
    assert_equal :dead, f1.state
    assert_equal :dead, f2.state
  end

  def test_select_with_interruption
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 1; :bar }
    spin { snooze; f2.interrupt(:baz) }
    result = Fiber.select(f1, f2)
    assert_equal [f2, :baz], result
  end
end

class SupervisionTest < MiniTest::Test
  def test_exception_during_termination
    f2 = nil
    f = spin do
      f2 = spin do
        sleep
      rescue Polyphony::Terminate
        raise 'foo'
      end
      sleep
    end

    sleep 0.01
    e = nil
    begin
      f.terminate
      f.await
    rescue => e
    end

    assert_kind_of RuntimeError, e
    assert_equal 'foo', e.message
    assert_equal f2, e.source_fiber
  end
end

class RestartTest < MiniTest::Test
  def test_restart
    buffer = []
    f = spin {
      buffer << 1
      receive
      buffer << 2
    }
    snooze
    assert_equal [1], buffer
    f2 = f.restart
    assert_equal f2, f
    assert_equal [1], buffer
    snooze
    assert_equal [1, 1], buffer
    
    f << 'foo'
    sleep 0.1
    assert_equal [1, 1, 2], buffer
  end

  def test_restart_after_finalization
    buffer = []
    parent = spin {
      sleep
    }

    f = parent.spin { |v|
      buffer << Fiber.current
      buffer << v
      buffer << receive
      buffer << :done
    }
    f.schedule('foo')
    f << 'bar'
    snooze
    f.await

    assert_equal [f, 'foo', 'bar', :done], buffer
    assert_equal parent, f.parent

    f2 = f.restart('baz')
    assert f2 != f
    assert_equal parent, f2.parent

    f2 << 42
    f2.await
    assert_equal [f, 'foo', 'bar', :done, f2, 'baz', 42, :done], buffer
  end
end
