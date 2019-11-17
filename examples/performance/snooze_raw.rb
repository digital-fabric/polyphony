# frozen_string_literal: true

require 'fiber'

def worker_loop(tag)
  loop do
    puts "#{Time.now} #{tag}"
    snooze
  end
end

f1 = Fiber.new { worker_loop(:a) }
f2 = Fiber.new { worker_loop(:b) }

$reactor = Fiber.new {
  loop {
    # sleep 0.001
    handle_next_tick
  }
}

$next_tick_items = []

def handle_next_tick
  items = $next_tick_items
  $next_tick_items = []
  items.each { |f| f.transfer }
end

module Kernel
  def snooze
    $next_tick_items << Fiber.current
    $reactor.transfer
  end
end

$next_tick_items << f1
$next_tick_items << f2
$reactor.transfer
