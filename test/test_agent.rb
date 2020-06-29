# frozen_string_literal: true

require_relative 'helper'

class AgentTest < MiniTest::Test
  def setup
    super
    @prev_agent = Thread.current.agent
    @agent = Polyphony::LibevAgent.new
    Thread.current.agent = @agent
  end

  def teardown
    @agent.finalize
    Thread.current.agent = @prev_agent
  end

  def test_sleep
    count = 0
    t0 = Time.now
    spin {
      @agent.sleep 0.01
      count += 1
    }
    suspend
    assert Time.now - t0 >= 0.01
    assert_equal 1, count
  end

  def test_write_read_partial
    i, o = IO.pipe
    buf = +''
    f = spin { @agent.read(i, buf, 5, false) }
    @agent.write(o, 'Hello world')
    return_value = f.await
    
    assert_equal 'Hello', buf
    assert_equal return_value, buf
  end

  def test_write_read_to_eof_limited_buffer
    i, o = IO.pipe
    buf = +''
    f = spin { @agent.read(i, buf, 5, true) }
    @agent.write(o, 'Hello')
    snooze
    @agent.write(o, ' world')
    snooze
    o.close
    return_value = f.await
    
    assert_equal 'Hello', buf
    assert_equal return_value, buf
  end

  def test_write_read_to_eof
    i, o = IO.pipe
    buf = +''
    f = spin { @agent.read(i, buf, 10**6, true) }
    @agent.write(o, 'Hello')
    snooze
    @agent.write(o, ' world')
    snooze
    o.close
    return_value = f.await
    
    assert_equal 'Hello world', buf
    assert_equal return_value, buf
  end

  def test_waitpid
    pid = fork do
      @agent.post_fork
      exit(42)
    end
    
    result = @agent.waitpid(pid)
    assert_equal [pid, 42], result
  end
end
