# frozen_string_literal: true

require 'fiber'
require_relative '../../lib/ev_ext'

module Core
  def self.trap(sig, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &callback)
  end

  def self.at_exit(&block)
    @exit_tasks ||= []
    @exit_tasks << block
  end

  def self.run_exit_procs
    return unless @exit_tasks

    @exit_tasks.each { |t| t.call rescue nil }
  end

  def self.run
    @sigint_watcher = trap(:int) do
      puts
      EV.break
    end
    EV.unref # the signal trap should not keep the loop running
    EV.run
    Core.run_exit_procs
  ensure
    @sigint_watcher.stop
    @sigint_watcher = nil
  end

  def self.auto_run
    return if @auto_ran
    @auto_ran = true
  
    return if $!

    run
  end

  def self.dont_auto_run!
    @auto_ran = true
  end
end

at_exit do
  Core.auto_run
end

class CoroutineInterrupt < Exception
  attr_reader :scope, :value

  def initialize(scope = nil, value = nil)
    @scope = scope
    @value = value
  end
end

class Stop < CoroutineInterrupt; end
class MoveOn < CoroutineInterrupt; end
class Cancel < CoroutineInterrupt; end

class CancelScope
  def initialize(opts = {})
    @opts = opts
    @error_class = @opts[:mode] == :cancel ? Cancel : MoveOn
  end

  def cancel!
    @fiber.resume @error_class.new(self, @opts[:value])
  end

  def start_timeout
    @timeout = EV::Timer.new(@opts[:timeout], 0)
    @timeout.start { cancel! }
  end

  def reset_timeout
    @timeout.reset
  end

  def call
    start_timeout if @opts[:timeout]
    @fiber = Fiber.current
    yield self
  rescue MoveOn => e
    puts "CancelScope#initialize MoveOn #{e.scope == self}"
    e.scope == self ? e.value : raise(e)
  ensure
    @timeout&.stop
  end
end

class Coroutine
  def initialize(&block)
    @block = block
  end

  def run
    @fiber = Fiber.new do
      @result = @block.call(self)
    rescue MoveOn => e
      puts "Coroutine#run MoveOn #{e.inspect}"
      @result = e.value
    ensure
      @fiber = nil
      @awaiting_fiber&.resume @result
    end
    
    @ran = true
    EV.next_tick { @fiber.resume }
    
    self
  end

  # Kernel.await expects the given argument / block to be a callable, so #call
  # in fact waits for the coroutine to finish
  def call
    run unless @ran
    if @fiber
      @awaiting_fiber = Fiber.current
      suspend
    else
      @result
    end
  end

  def to_proc
    -> { call }
  end

  def interrupt(klass)
    @fiber&.resume(klass.new)
  end
end

class SupervisorAgent
  attr_writer :supervisor_fiber

  def initialize
    @coroutines = []
  end

  def spawn(proc = nil, &block)
    block ||= proc
    @coroutines << Object.spawn do |coroutine|
      block.call(coroutine)
      task_completed(coroutine)
    rescue Exception => e
      task_completed(coroutine)
    end
  end

  def task_completed(coroutine)
    return unless @coroutines.include?(coroutine)
    
    @coroutines.delete(coroutine)
    puts "@coroutines.empty? = true, @supervisor_fiber = #{@supervisor_fiber.inspect}" if @coroutines.empty?
    @supervisor_fiber&.resume if @coroutines.empty?
  end

  def stop_all_tasks
    @coroutines.each do |c|
      EV.next_tick { c.interrupt(Stop) }
    end
  end

  def still_running?
    !@coroutines.empty?
  end

  def stop!(result = nil)
    return unless @supervisor_fiber
  
    puts "stop!(#{result.inspect})"
    @supervisor_fiber&.resume MoveOn.new(nil, result)
  end
end

def supervisor(&block)
  agent = SupervisorAgent.new
  proc do |&block2|
    agent.supervisor_fiber = Fiber.current
    (block || block2).(agent)
    suspend
  rescue MoveOn => e
    puts "#supervisor MoveOn #{e.value.inspect}"
    e.value
  ensure
    agent.stop_all_tasks
    suspend if agent.still_running?
  end
end

module Kernel
  def spawn(proc = nil, &block)
    Coroutine.new(&(block || proc)).run
  end

  def await(proc = nil, &block)
    if proc && block
      proc.(&block)
    else
      (block || proc).()
    end
  end

  def sleep(duration)
    proc do
      timer = EV::Timer.new(duration, 0)
      timer.await
    ensure
      timer.stop
    end
  end

  def suspend
    result = Fiber.yield
    result.is_a?(Exception) ? raise(result) : result
  end

  def timeout(duration, opts = {}, &block)
    CancelScope.new(opts.merge(timeout: duration)).(&block)
  end

  def move_on_after(duration, &block)
    CancelScope.new(timeout: duration).(&block)
  end

  def cancel_after(duration, &block)
    CancelScope.new(timeout: duration, mode: :cancel).(&block)
  end

  def supervise(&block)
    supervisor(&block)
  end
end

def sleep_and_stop_supervisor(duration, supervisor, cancel_scope)
  puts "sleep  #{duration}"
  await sleep(duration)
  puts "wakeup #{duration}"
  cancel_scope.reset_timeout
  supervisor.stop!(duration)
end

cr = Coroutine.new do
  puts "going to sleep"
  await sleep(1)
  puts "woke up"
end

# r = spawn do
#   p 1
#   cr.run
#   await cr
#   p 2
# end
# p r

# spawn do
#   result = move_on_after(0.5) do |scope|
#     await supervise do |supervisor|
#       (1..3).each do |d|
#         supervisor.spawn { sleep_and_stop_supervisor(d, supervisor, scope) }
#       end
#     end
#   end
#   puts "result: #{result}"
# end