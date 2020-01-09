# frozen_string_literal: true

require 'bundler/setup'
require 'fiber'

## An experiment to see if the Coprocess class could be implemented as an
## extension for the stock Fiber (since it's already enhanced)

class Fiber
  def self.spin(&block)
    new(&wrap_block(block)).set_block(block).tap { |f| f.schedule }
  end

  attr_accessor :__block__

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
    Fiber.run_next_fiber
  rescue Exception => e
    @running = nil
    parent_fiber = calling_fiber.running? ? calling_fiber : Fiber.main_fiber
    parent_fiber.transfer(e)
  end

  def running?
    @running
  end

  def set_block(block)
    @__block__ = block
    self
  end

  def inspect
    if @__block__
      "<Fiber:#{object_id} #{@__block__.source_location.join(':')} (#{__scheduled_value__.inspect})>"
    else
      "<Fiber:#{object_id} (main) (#{__scheduled_value__.inspect})>"
    end
  end
  alias_method :to_s, :inspect

  # scheduling
  @@scheduled_head = nil
  @@scheduled_tail = nil

  attr_accessor :__scheduled_next__
  attr_accessor :__scheduled_value__

  def self.snooze
    current.schedule
    yield_to_next
  end

  def self.suspend
    yield_to_next
  end

  @@main_fiber = Fiber.current

  def self.main_fiber
    @@main_fiber
  end

  def self.yield_to_next
    v = Fiber.run_next_fiber
    v.is_a?(Exception) ? (raise v) : v
  end

  def self.run_next_fiber
    unless @@scheduled_head
      return main_fiber.transfer
    end

    next_fiber = @@scheduled_head
    next_next_fiber = @@scheduled_head.__scheduled_next__
    next_fiber.__scheduled_next__ = nil
    if next_next_fiber
      @@scheduled_head = next_next_fiber
    else
      @@scheduled_head = @@scheduled_tail = nil
    end
    next_fiber.transfer(next_fiber.__scheduled_value__)
  end

  def schedule(value = nil)
    @__scheduled_value__ = value
    if @@scheduled_head
      @@scheduled_tail.__scheduled_next__ = self
      @@scheduled_tail = self
    else
      @@scheduled_head = @@scheduled_tail = self
    end
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

f1 = Fiber.spin {
  p Fiber.current
  Fiber.snooze
  3.times {
    STDOUT << '*'
    Fiber.snooze
  }
  :foo
}

f2 = Fiber.spin {
  p Fiber.current
  Fiber.snooze
  10.times {
    STDOUT << '.'
    Fiber.snooze
  }
}

# v = f1.await
# puts "done waiting #{v.inspect}"

Fiber.suspend