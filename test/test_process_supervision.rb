# frozen_string_literal: true

require_relative 'helper'

class ProcessSupervisionTest < MiniTest::Test
  def test_process_supervisor_with_block
    i, o = IO.pipe

    f = spin do
      Polyphony.watch_process do
        i.close
        sleep 5
      ensure
        o << 'foo'
        o.close
      end
      supervise(on_error: :restart)
    end

    sleep 0.05
    f.terminate
    f.await

    o.close
    msg = i.read
    i.close
    assert_equal 'foo', msg
  end

  def test_process_supervisor_with_cmd
    fn = '/tmp/test_process_supervisor_with_cmd'
    FileUtils.rm(fn) rescue nil

    f = spin do
      Polyphony.watch_process("echo foo >> #{fn}")
      supervise(on_error: :restart)
    end

    sleep 0.05
    f.terminate
    f.await

    assert_equal "foo\n", IO.read(fn)

  end
end