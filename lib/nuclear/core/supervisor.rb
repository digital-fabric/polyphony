# frozen_string_literal: true

export_default :Supervisor

Exceptions  = import('./exceptions')
FiberPool   = import('./fiber_pool')
Task        = import('./task')

class Supervisor < Task
  def initialize(opts = {}, &block)
    @children = []
    @pending = []
    @opts = {}
    @block = block
  end

  # Adds the given task to the supervisor. This method is usually called inside
  # Kernel#supervise, i.e.:
  #
  #     await supervise do |s|
  #       s << async { ... }
  #       ...
  #     end
  #
  # @param task [Task, Proc] asynchronous task
  # @return [void]
  def <<(task)
    task = async(&task) unless task.is_a?(Task)
    task.supervisor = self
    @children << task
    @pending << task
    task.start unless task.running?
  end

  def run
    @fiber = Fiber.current
    @block&.(self)
  ensure
    @fiber = nil
  end

  def task_stopped(task, result)
    @pending.delete(task)
    @awaiting_fiber&.resume(@result) if @pending.empty?
  end

  def stop!(result = nil)
    @fiber&.resume Exceptions::Stopped.new
    EV.next_tick {
      puts "set result: #{result.inspect}"
      @result = result
      @pending.slice(0..-1).each(&:stop!)
    }
  end

  def cancel!
    @pending.slice(0..-1).each(&:cancel!)
  end
end
