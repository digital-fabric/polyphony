# frozen_string_literal: true

export_default :Supervisor

Coroutine   = import('./coroutine')
Exceptions  = import('./exceptions')

class Supervisor
  def initialize
    @coroutines = []
  end

  def call(&block)
    proc do |&block2|
      @supervisor_fiber = Fiber.current
      (block || block2).(self)
      suspend
    rescue Exceptions::MoveOn => e
      e.value
    ensure
      stop_all_tasks
      suspend if still_running?
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
  
    @supervisor_fiber&.resume Exceptions::MoveOn.new(nil, result)
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
    @supervisor_fiber&.resume if @coroutines.empty?
  end
end
