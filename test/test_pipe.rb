# frozen_string_literal: true

require_relative 'helper'

class PipeTest < MiniTest::Test
  def test_pipe_creation
    pipe = Polyphony::Pipe.new

    fds = pipe.fds
    assert_equal 2, fds.size
    assert_kind_of Integer, fds[0]
    assert_kind_of Integer, fds[1]
    assert_equal false, pipe.closed?
  end

  def test_polyphony_pipe_method
    pipe = Polyphony.pipe

    fds = pipe.fds
    assert_equal 2, fds.size
    assert_kind_of Integer, fds[0]
    assert_kind_of Integer, fds[1]
    assert_equal false, pipe.closed?
  end

  def test_pipe_splice
    src = Polyphony::Pipe.new
    dest = Polyphony::Pipe.new

    spin {
      trace(tes_pipe_splice: 1)
      IO.splice(src, dest, 8192)
      trace(tes_pipe_splice: 2)
      dest.close
      trace(tes_pipe_splice: 3)
    }

    trace(tes_pipe_splice: 4)
    src << IO.read(__FILE__)
    trace(tes_pipe_splice: 5)
    src.close
    trace(tes_pipe_splice: 6)

    data = dest.read
    trace(tes_pipe_splice: 7)
    assert_equal IO.read(__FILE__), data
  end
end
