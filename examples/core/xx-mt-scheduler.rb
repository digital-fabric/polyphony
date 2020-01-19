# frozen_string_literal: true

require 'fiber'

## An experiment to see if the Coprocess class could be implemented as an
## extension for the stock Fiber (since it's already enhanced)

class Thread
  attr_accessor :main_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args, &block)
    orig_initialize do
      Fiber.current.setup_main_fiber
      block.(*args)
    end
  end

  def fiber_scheduler
    @fiber_scheduler ||= Scheduler.new
  end
end

class Scheduler
  def initialize
    # @mutex = Mutex.new
    @queue = Queue.new
  end

  def <<(fiber)
    @queue << fiber
    # @mutex.synchronize do
    #   if @head
    #     @tail.__scheduled_next__ = @tail = fiber
    #   else
    #     @head = @tail = fiber
    #   end
    # end
  end

  def switch
    next_fiber = nil
    while true
      next_fiber = @queue.empty? ? Thread.current.main_fiber : @queue.pop# unless @queue.empty?
      # next_fiber = @queue.empty? ? nil : @queue.pop
      # puts "next_fiber: #{next_fiber.inspect}"
      # next_fiber = @mutex.synchronize { @head }
      break if next_fiber
      sleep 0
    end

    # next_next_fiber = next_fiber.__scheduled_next__
    # next_fiber.__scheduled_next__ = nil
    next_fiber.__scheduled__ = nil
    # @mutex.synchronize { @head = next_next_fiber || (@tail = nil) }
    next_fiber.transfer(next_fiber.__scheduled_value__)
  end

  def handle_events
  end
end

class Fiber
  def self.spin(&block)
    new(&wrap_block(block)).setup(block)
  end

  attr_accessor :__block__
  attr_reader :scheduler

  def self.wrap_block(block)
    calling_fiber = Fiber.current
    proc { |v| Fiber.current.run(v, calling_fiber, &block) }
  end

  def run(v, calling_fiber)
    raise v if v.is_a?(Exception)

    @running = true
    result = yield v
    @running = nil
    schedule_waiting_fibers(result)
    @scheduler.switch
  rescue Exception => e
    @running = nil
    parent_fiber = calling_fiber.running? ? calling_fiber : Thread.current.main_fiber
    parent_fiber.transfer(e)
  end

  def running?
    @running
  end

  def setup(block)
    @scheduler = Thread.current.fiber_scheduler
    @__block__ = block
    schedule
    self
  end

  def setup_main_fiber
    @scheduler = Thread.current.fiber_scheduler
    Thread.current.main_fiber = self
  end

  Fiber.current.setup_main_fiber

  attr_reader :__scheduled_value__
  # attr_accessor :__scheduled_next__
  attr_accessor :__scheduled__

  def inspect
    if @__block__
      "<Fiber:#{object_id} #{@__block__.source_location.join(':')} (#{@__scheduled_value__.inspect})>"
    else
      "<Fiber:#{object_id} (main) (#{@__scheduled_value__.inspect})>"
    end
  end
  alias_method :to_s, :inspect

  def self.snooze
    current.schedule
    yield_to_next
  end

  def self.suspend
    yield_to_next
  end

  def self.yield_to_next
    v = current.scheduler.switch
    v.is_a?(Exception) ? (raise v) : v
  end

  def schedule(value = nil)
    return if @__scheduled__

    @__scheduled__ = true
    @__scheduled_value__ = value
    @scheduler << self
  end

  def await
    current_fiber = Fiber.current
    if @waiting_fiber
      if @waiting_fiber.is_a?(Array)
        @waiting_fiber << current_fiber
      else
        @waiting_fiber = [@waiting_fiber, current_fiber]
      end
    else
      @waiting_fiber = current_fiber
    end
    Fiber.suspend
  end

  def schedule_waiting_fibers(v)
    case @waiting_fiber
    when Array then @waiting_fiber.each { |f| f.schedule(v) }
    when Fiber then @waiting_fiber.schedule(v)
    end
  end
end

# f1 = Fiber.spin {
#   p Fiber.current
#   Fiber.snooze
#   3.times {
#     STDOUT << '*'
#     Fiber.snooze
#   }
#   :foo
# }

# f2 = Fiber.spin {
#   p Fiber.current
#   Fiber.snooze
#   10.times {
#     STDOUT << '.'
#     Fiber.snooze
#   }
#   puts
# }

# v = f1.await
# puts "done waiting #{v.inspect}"

def test_single_thread(x, y)
  x.times {
    Fiber.spin {
      y.times { |i| Fiber.snooze }
    }
  }

  Fiber.suspend
end

def spin_char(char)
  Fiber.spin {
    loop {
      STDOUT << char
      Fiber.snooze
    }
  }
end

def test_two_threads
  Thread.new {
    spin_char('.')
    spin_char(':')
    Fiber.suspend
  }

  Thread.new {
    spin_char('*')
    spin_char('@')
    Fiber.suspend
  }
end

# test_two_threads
# sleep

def test_perf(x, y)
  puts "* #{x} fibers #{y} times"
  3.times do
    t0 = Time.now
    # test_single_thread(1, 1000)
    test_single_thread(x, y)
    elapsed = Time.now - t0
    rate = (x * y / (Time.now - t0)).to_i
    puts "#{rate} switches/sec"
  end
end

loop {
  test_perf(1, 100000)
}
test_perf(10, 10000)
test_perf(100, 1000)
test_perf(1000, 100)
test_perf(10000, 10)
exit!

def ping_pong
  STDOUT.sync = true
  f1 = nil
  f2 = nil
  count1 = 0
  count2 = 0

  Thread.new do
    f1 = Fiber.spin {
      loop {
        count1 += 1
        # STDOUT << '.'
        f2&.schedule
        Fiber.suspend
      }
    }
    Fiber.suspend
  end

  Thread.new do
    f2 = Fiber.spin {
      loop {
        count2 += 1
        # STDOUT << '*'
        f1&.schedule
        Fiber.suspend
      }
    }
    Fiber.suspend
  end

  Thread.new do
    last_count1 = 0
    last_count2 = 0
    last_t = Time.now
    loop {
      sleep 1
      t = Time.now
      e = t - last_t
      c1 = count1
      c2 = count2
      delta1 = c1 - last_count1
      delta2 = c2 - last_count2
      rate1 = (delta1.to_f / e).to_i
      rate2 = (delta2.to_f / e).to_i
      puts "#{rate1} #{rate2} (#{rate1 + rate2})"
      last_count1 = c1
      last_count2 = c2
      last_t = t
    }
  end
end

ping_pong
sleep
exit!

def ping_pong_st
  STDOUT.sync = true
  f1 = nil
  f2 = nil
  count1 = 0
  count2 = 0

  f1 = Fiber.spin {
    loop {
      count1 += 1
      # STDOUT << '.'
      f2&.schedule
      Fiber.suspend
    }
  }

  f2 = Fiber.spin {
    last_count1 = 0
    last_count2 = 0
    last_t = Time.now

    loop {
      count2 += 1
      # STDOUT << '*'
      f1&.schedule
      Fiber.suspend

      next unless count2 % 100000 == 0

      t = Time.now
      e = t - last_t
      c1 = count1
      c2 = count2
      delta1 = c1 - last_count1
      delta2 = c2 - last_count2
      rate1 = (delta1.to_f / e).to_i
      rate2 = (delta2.to_f / e).to_i
      puts "#{rate1} #{rate2} (#{rate1 + rate2})"
      last_count1 = c1
      last_count2 = c2
      last_t = t
    }
  }

end

ping_pong_st
Fiber.suspend