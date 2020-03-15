# frozen_string_literal: true

require_relative 'helper'

class ProcessSupervisorTest < MiniTest::Test
  def test_process_supervisor_with_block
    i, o = IO.pipe

    f = spin do
      # pid = Polyphony.fork do
      Polyphony::ProcessSupervisor.supervise do
        i.close
        sleep 5
      ensure
        o << 'foo'
        o.close
      end
    end

    sleep 0.05
    f.terminate
    f.await

    o.close
    msg = i.read
    i.close
    assert_equal 'foo', msg
  end
end