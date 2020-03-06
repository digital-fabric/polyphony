# frozen_string_literal: true

require_relative 'helper'

class SignalTest < MiniTest::Test
  def test_Gyro_Signal_constructor
    sig = Signal.list['USR1']
    count = 0
    w = Gyro::Signal.new(sig)

    spin {
      loop {
        w.await
        count += 1
        break
      }
    }
    Thread.new do
      orig_sleep 0.001
      Process.kill(:USR1, Process.pid)
    end
    suspend
    assert_equal 1, count
  end

  def test_wait_for_signal_api
    count = 0
    spin do
      Polyphony.wait_for_signal 'SIGHUP'
      count += 1
    end

    snooze
    Process.kill(:HUP, Process.pid)
    snooze
    assert_equal 1, count
  end
end

class SignalTrapTest < Minitest::Test
  def test_signal_exception_handling
    i, o = IO.pipe
    pid = Polyphony.fork do
      i.close
      spin do
        spin do
          sleep 1
        rescue ::Interrupt => e
          # the signal will be trapped in the context of this fiber
          o.puts "1-interrupt"
          raise e
        end.await
      end.await
    rescue ::Interrupt => e
      o.puts "3-interrupt"
    ensure
      o.close
    end
    sleep 0.01
    o.close
    watcher = Gyro::Child.new(pid)
    Process.kill('INT', pid)
    watcher.await
    buffer = i.read
    assert_equal "3-interrupt\n", buffer
  end

  def test_signal_exception_with_cleanup
    i, o = IO.pipe
    pid = Polyphony.fork do
      i.close
      spin do
        spin do
          sleep
        rescue Polyphony::Terminate
          o.puts "1 - terminated"
        end.await
      rescue Polyphony::Terminate
        o.puts "2 - terminated"
      end.await
    rescue Interrupt
      o.puts "3 - interrupted"
      Fiber.current.terminate_all_children
      Fiber.current.await_all_children
    ensure
      o.close
    end
    sleep 0.02
    o.close
    watcher = Gyro::Child.new(pid)
    Process.kill('INT', pid)
    watcher.await
    buffer = i.read
    assert_equal "3 - interrupted\n2 - terminated\n1 - terminated\n", buffer
  end

  def test_signal_exception_possible_race_condition
    i, o = IO.pipe
    pid = Polyphony.fork do
      i.close
      f1 = nil
      f2 = spin do
        # this fiber will try to create a race condition by
        # - being scheduled before f1 is scheduled with the Interrupt exception
        # - scheduling f1 without an exception
        suspend
        f1.schedule
      rescue ::Interrupt => e
        o.puts '2-interrupt'
        raise e
      end
      f1 = spin do
        # this fiber is the one that will be current when the
        # signal is trapped
        sleep 1
        o << 'boom'
      rescue ::Interrupt => e
        o.puts '1-interrupt'
        raise e
      end
      old_trap = trap('INT') do
        f2.schedule
        old_trap.()
      end
      Fiber.current.await_all_children
    rescue ::Interrupt => e
      o.puts '3-interrupt'
    ensure
      o.close
    end
    o.close
    sleep 0.1
    Process.kill('INT', pid)
    Gyro::Child.new(pid).await
    buffer = i.read
    assert_equal "3-interrupt\n", buffer
  end
end