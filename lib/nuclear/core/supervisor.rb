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
  # @param task [Proc] asynchronous task
  # @return [void]
  def <<(task)
    task = async { task } unless task.is_a?(Task)
    task.supervisor = self
    @children << task
    @pending << task
    task.start
  end

  def run
    @block&.(self)
  end

  def task_stopped(task, result)
    @pending.delete(task)
    if @pending.empty?
      @awaiting_fiber&.resume true
    end
  end

  def stop!
    @pending.slice(0..-1).each(&:stop!)
  end

  def cancel!
    @pending.slice(0..-1).each(&:cancel!)
  end
end
