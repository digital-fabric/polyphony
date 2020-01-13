# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Thread.event_selector = ->(thread) { Gyro::Selector.new(thread) }

def bm(sym, x)
  t0 = Time.now
  send(sym, x)
  elapsed = Time.now - t0
  STDOUT.orig_puts "#{sym} #{x / elapsed}"
end

def test_queue(x)
  queue = Queue.new
  async = Gyro::Async.new
  t1 = Thread.new do
    Thread.current.setup_fiber_scheduling
    counter = 0
    loop {
      async.await if queue.empty?
      v = queue.pop
      counter += 1
      break if counter == x
    }
  ensure
    Thread.current.stop_event_selector
  end
  t2 = Thread.new do
    Thread.current.setup_fiber_scheduling
    x.times { |i|
      queue.push i
      async.signal!
    }
  ensure
    Thread.current.stop_event_selector
  end
  t1.join
  t2.join
end

def test_array_mutex(x)
  queue = []
  mutex = Mutex.new
  async = Gyro::Async.new
  t1 = Thread.new {
    Thread.current.setup_fiber_scheduling
    counter = 0
    loop {
      async.await if mutex.synchronize { queue.empty? }
      v = mutex.synchronize { queue.shift }
      counter += 1
      break if counter == x
    }
  }
  t2 = Thread.new {
    Thread.current.setup_fiber_scheduling
    x.times { |i|
      mutex.synchronize { queue.push i }
      async.signal!
    }
  }
  t1.join
  t2.join
end

# class Gyro::Queue
#   def initialize
#     @wait_queue = []
#     @queue = []
#   end

#   def <<(value)
#     async = @wait_queue.pop
#     if async
#       async.signal! value
#     else
#       @queue.push value
#     end
#   end

#   def shift
#     if @queue.empty?
#       async = Gyro::Async.new
#       @wait_queue << async
#       async.await
#     else
#       @queue.shift
#     end
#   end
# end

def test_gyro_queue(x)
  queue = Gyro::Queue.new
  x.times { |i| queue << i }
  t1 = Thread.new do
    Thread.current.setup_fiber_scheduling
    x.times { queue.shift }
  ensure
    Thread.current.stop_event_selector
  end
  t2 = Thread.new do
    Thread.current.setup_fiber_scheduling
    x.times { |i| queue << i }
  ensure
    Thread.current.stop_event_selector
  end
  t1.join
  t2.join
end

Thread.current.setup_fiber_scheduling
# bm(:test_array_mutex,     1000000)
loop {
  STDOUT.orig_puts "*" * 40
  bm(:test_queue,           1000000)
  bm(:test_gyro_queue,      1000000)
}

