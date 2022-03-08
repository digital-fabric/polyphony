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
      IO.splice(src, dest, 8192)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close
  
    data = dest.read
    assert_equal IO.read(__FILE__), data
  end
end
