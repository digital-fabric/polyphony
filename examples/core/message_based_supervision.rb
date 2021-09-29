# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

class Supervisor
  def initialize(*fibers)
    @fiber = spin { do_supervise }
    @fiber.message_on_child_termination = true
    fibers.each { |f| add(f) }
  end

  def await
    @fiber.await
  end

  def spin(tag = nil, &block)
    @fiber.spin(tag, &block)
  end

  def add(fiber)
    fiber.attach(@fiber)
  end

  def do_supervise
    loop do
      msg = receive
      # puts "Supervisor received #{msg.inspect}"
      f, r = msg
      puts "Fiber #{f.tag} terminated with #{r.inspect}, restarting..."
      f.restart
    end
  end
end

def supervise(*fibers)
  supervisor = Supervisor.new(*fibers)
  supervisor.await
end

def start_worker(id)
  spin_loop(:"worker#{id}") do
    duration = rand(0.5..1.0)
    puts "Worker #{id} sleeping for #{duration} seconds"
    sleep duration
    raise 'foo' if rand > 0.7
    break if rand > 0.6
  end
end

supervise(start_worker(1), start_worker(2))
