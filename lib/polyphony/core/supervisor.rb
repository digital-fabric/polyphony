# frozen_string_literal: true

export_default :Supervisor

Coprocess   = import('./coprocess')
Exceptions  = import('./exceptions')

# Implements a supervision mechanism for controlling multiple coprocesses
class Supervisor
  def initialize
    @coprocesses = []
    @pending = []
  end

  def await(&block)
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
    @coprocesses.map { |cp| cp.result }
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

  def spin(coproc = nil, &block)
    coproc = Coprocess.new(&(coproc || block)) unless coproc.is_a?(Coprocess)
    @coprocesses << coproc
    @pending << coproc
    coproc.when_done { task_completed(coproc) }
    coproc.run unless coproc.alive?
    coproc
  end

  def add(coproc)
    @coprocesses << coproc
    @pending << coproc
    coproc.when_done { task_completed(coproc) }
    coproc.run unless coproc.alive?
    coproc
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
    @pending.each do |c|
      c.transfer(exception)
    end
  end

  def task_completed(coprocess)
    return unless @pending.include?(coprocess)

    @pending.delete(coprocess)
    @supervisor_fiber&.transfer if @pending.empty?
  end
end

class Coprocess
  def self.await(*coprocs)
    supervise do |s|
      coprocs.each { |cp| s.add cp }
    end
  end
end