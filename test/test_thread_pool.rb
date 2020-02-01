# frozen_string_literal: true

require_relative 'helper'

class ThreadPoolTest < MiniTest::Test
  def setup
    super
    # @pool = Polyphony::ThreadPool.new
  end

  def test_process
    skip
    current_thread = Thread.current

    processing_thread = nil
    result = @pool.process do
      processing_thread = Thread.current
      +'foo' + 'bar'
    end
    assert_equal 'foobar', result
    assert processing_thread != current_thread
  end

  def test_multi_process
    skip
    current_thread = Thread.current
    threads = []
    results = []

    10.times do |i|
      spin do
        results << @pool.process do
          threads << Thread.current
          sleep 0.01
          i * 10
        end
      end
    end

    suspend

    assert_equal @pool.size, threads.uniq.size
    assert_equal (0..9).map { |i| i * 10}, results.sort
  end

  def test_process_with_exception
    skip
    result = nil
    begin
      result = @pool.process { raise 'foo' }
    rescue => result
    end

    assert_kind_of RuntimeError, result
    assert_equal 'foo', result.message
  end

  def test_cast
    skip
    t0 = Time.now
    threads = []
    buffer = []
    10.times do |i|
      @pool.cast do
        sleep 0.01
        threads << Thread.current
        buffer << i
      end
    end
    elapsed = Time.now - t0

    assert elapsed < 0.005
    assert buffer.size < 2
    
    sleep 0.05
    assert_equal @pool.size, threads.uniq.size
    assert_equal (0..9).to_a, buffer.sort
  end
end
