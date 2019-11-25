# frozen_string_literal: true

export_default :Supervisor

Coprocess   = import('./coprocess')
Exceptions  = import('./exceptions')

# Implements a supervision mechanism for controlling multiple coprocesses
class Supervisor
  def initialize
    @coprocesses = []
  end

  def await(&block)
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    finalize_await
  end

  def finalize_await
    if still_running?
      stop_all_tasks
      suspend
    else
      @supervisor_fiber = nil
    end
  end

  def spin(proc = nil, &block)
    proc = Coprocess.new(&(proc || block)) unless proc.is_a?(Coprocess)
    @coprocesses << proc
    proc.when_done { task_completed(proc) }
    proc.run unless proc.alive?
    proc
  end

  def still_running?
    !@coprocesses.empty?
  end

  def stop!(result = nil)
    return unless @supervisor_fiber && !@stopped

    @stopped = true
    @supervisor_fiber.transfer Exceptions::MoveOn.new(nil, result)
  end

  def stop_all_tasks
    exception = Exceptions::MoveOn.new
    @coprocesses.each do |c|
      c.transfer(exception)
    end
  end

  def task_completed(coprocess)
    return unless @coprocesses.include?(coprocess)

    @coprocesses.delete(coprocess)
    @supervisor_fiber&.transfer if @coprocesses.empty?
  end
end
