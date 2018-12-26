# frozen_string_literal: true

export_default :Supervisor

Coroutine   = import('./coroutine')
Exceptions  = import('./exceptions')

class Supervisor
  def initialize
    @coroutines = []
  end

  def await(&block)
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    if still_running?
      stop_all_tasks
      suspend
    else
      @supervisor_fiber = nil
    end
  end

  def spawn(proc = nil, &block)
    if proc.is_a?(Coroutine)
      spawn_coroutine(proc)
    else
      spawn_proc(block || proc)
    end
  end

  def spawn_coroutine(proc)
    @coroutines << proc
    proc.when_done { task_completed(proc) }
    proc.run unless proc.running?
    proc
  end

  def spawn_proc(proc)
    @coroutines << Object.spawn do |coroutine|
      proc.call(coroutine)
      task_completed(coroutine)
    rescue Exception => e
      task_completed(coroutine)
    end
  end

  def still_running?
    !@coroutines.empty?
  end

  def stop!(result = nil)
    return unless @supervisor_fiber
  
    @supervisor_fiber&.transfer Exceptions::MoveOn.new(nil, result)
  end

  def stop_all_tasks
    exception = Exceptions::Stop.new
    @coroutines.each do |c|
      EV.next_tick { c.interrupt(exception) }
    end
  end

  def task_completed(coroutine)
    return unless @coroutines.include?(coroutine)
    
    @coroutines.delete(coroutine)
    @supervisor_fiber&.transfer if @coroutines.empty?
  end
end
