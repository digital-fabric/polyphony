# frozen_string_literal: true

require_relative 'helper'

class ProcessSupervisionTest < MiniTest::Test
  def test_process_supervisor_with_block
    i, o = IO.pipe

    watcher = spin do
      Polyphony.watch_process do
        i.close
        sleep 5
      ensure
        o << 'foo'
        o.close
      end
    end

    supervisor = spin { supervise(watcher, restart: :always) }

    sleep 0.05
    supervisor.terminate
    supervisor.await

    o.close
    msg = i.read
    assert_equal 'foo', msg
  end

  def test_process_supervisor_restart_with_block
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe

    count = 0
    watcher = spin do
      count += 1
      Polyphony.watch_process do
        i1.gets
        o2.puts count
      end
    end

    supervisor = spin { supervise(watcher, restart: :always) }

    o1.puts
    l = i2.gets
    assert_equal "1\n", l

    o1.puts
    l = i2.gets
    assert_equal "2\n", l

    o1.puts
    l = i2.gets
    assert_equal "3\n", l
  end

  def test_process_supervisor_with_cmd
    fn = '/tmp/test_process_supervisor_with_cmd'
    FileUtils.rm(fn) rescue nil

    watcher = spin do
      Polyphony.watch_process("echo foo >> #{fn}")
    end

    supervisor = spin { supervise(watcher) }

    sleep 0.2
    supervisor.terminate
    supervisor.await

    assert_equal "foo\n", IO.read(fn)

  end
end
