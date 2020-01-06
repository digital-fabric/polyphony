# frozen_string_literal: true

export_default :Supervisor

Coprocess   = import('./coprocess')
Exceptions  = import('./exceptions')

# Implements a supervision mechanism for controlling multiple coprocesses
class Supervisor
  def initialize(&block)
    @coprocesses = []
    @pending = {}
  end

  def await(&block)
    @mode = :await
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
    @coprocesses.map(&:result)
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    finalize_await
  end
  alias_method :join, :await

  def select(&block)
    @mode = :select
    @select_coproc = nil
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
    [@select_coproc.result, @select_coproc]
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    stop_all_tasks if still_running?
    @supervisor_fiber = nil
  end

  def finalize_await
    if still_running?
      stop_all_tasks
      suspend
    else
      @supervisor_fiber = nil
    end
  end

  def spin(coproc = nil, &block)
    coproc = Coprocess.new(&(coproc || block)) unless coproc.is_a?(Coprocess)
    @coprocesses << coproc
    @pending[coproc] = true
    coproc.when_done { task_completed(coproc) }
    coproc.run unless coproc.alive?
    coproc
  end

  def add(coproc)
    @coprocesses << coproc
    @pending[coproc] = true
    coproc.when_done { task_completed(coproc) }
    coproc.run unless coproc.alive?
    coproc
  end
  alias_method :<<, :add

  def still_running?
    !@pending.empty?
  end

  def interrupt(result = nil)
    return unless @supervisor_fiber && !@stopped

    @stopped = true
    @supervisor_fiber.schedule Exceptions::MoveOn.new(nil, result)
  end
  alias_method :stop, :interrupt

  def stop_all_tasks
    exception = Exceptions::MoveOn.new
    @pending.each_key do |c|
      c.schedule(exception)
    end
  end

  def task_completed(coprocess)
    return unless @pending[coprocess]

    # puts "task_completed #{coprocess.inspect}"

    @pending.delete(coprocess)
    return unless @pending.empty? || (@mode == :select && !@select_coproc)
    
    # puts "scheduling supervisor fiber"
    # p [@pending.empty?, @mode == :select, !@select_coproc]
    @select_coproc = coprocess if @mode == :select
    @supervisor_fiber&.schedule
  end
end

# Extension for Coprocess class
class Coprocess
  class << self
    def await(*coprocs)
      supervisor = Supervisor.new
      coprocs.each { |cp| supervisor << cp }
      supervisor.await
    end
    alias_method :join, :await

    def select(*coprocs)
      supervisor = Supervisor.new
      coprocs.each { |cp| supervisor << cp }
      supervisor.select
    end
  end
end
