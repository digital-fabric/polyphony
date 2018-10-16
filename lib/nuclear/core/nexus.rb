# frozen_string_literal: true

export_default :Nexus

FiberPool = import('./fiber_pool')

# Encapsulates a group of related asynchronous tasks with means for controlling
# their execution.
class Nexus
  def initialize(tasks = nil, &block)
    @tasks = tasks || []
    @fibers = []
    @completed = []
    @block = block
  end

  # Adds the given task to the nexus. This method is usually called inside
  # Kernel#nexus, i.e.:
  #
  #     await nexus do |n|
  #       n << async { ... }
  #     end
  #
  # @param task [Proc] asynchronous task
  # @return [void]
  def <<(task)
    @tasks << task
  end

  # Returns an asynchronous task for running the nexus
  # @return [Proc]
  def to_proc
    method(:run_nexus)
  end

  # Runs the nexus with an optional block
  # @return [any] result of running the nexus
  def run_nexus(&block2)
    (block2 || @block)&.(self)
    @tasks.each { |t| start_sub_task(t) }
    @nexus_fiber = Fiber.current
    Fiber.yield_and_raise_error
  rescue Exception => e
    cancel_sub_tasks(Cancelled.new(nil, nil)) unless @cancelled
    e.is_a?(MoveOn) ? e.value : raise(e)
  end

  # Starts an asynchronous sub task
  # @param task [Proc] sub task
  # @return [void]
  def start_sub_task(task)
    if task.async
      run_async_proc(task)
    else
      EV.next_tick do
        FiberPool.spawn { |fiber| run_async_sub_task(fiber, task) }
      end
    end
  end

  # Runs an async proc normally returned by Kernel#async
  # @param task [Proc] async task
  # @return [void]
  def run_async_proc(task)
    task.(
      no_block: true,
      on_start: proc { |fiber| @fibers << fiber },
      on_done: proc { |fiber, result| task_completed(fiber, result) }
    )
  end

  # Runs an async task
  # @param fiber [Fiber] fiber on which the task will run
  # @param task [Proc] async task
  # @return [void]
  def run_async_sub_task(fiber, task)
    @fibers << fiber
    result = await task
    task_completed(fiber, result)
  rescue Exception => e
    puts "error: #{e}"
    task_completed(fiber, e) unless @cancelled
  end

  # Cancels execution of nexus tasks
  # @param error [Exception] exception to pass to sub tasks
  # @return [void]
  def cancel_sub_tasks(error)
    @cancelled = true
    @fibers.each { |f| f.resume(error) }
  end

  # Method called upon completion of a sub task
  # @param fiber [Fiber] fiber used to run the sub task
  # @param result [any] result of running the sub task
  # @return [void]
  def task_completed(fiber, result)
    return if @cancelled

    @fibers.delete(fiber)
    if result.is_a?(Exception)
      @nexus_fiber&.resume(result)
    elsif @fibers.empty?
      @nexus_fiber&.resume(@tasks.size)
    end
  end

  # Cancels the execution of the nexus using a MoveOn exception
  # @param value [any] value to use as result of nexus task
  def move_on!(value)
    @nexus_fiber&.resume(MoveOn.new(nil, value))
  end
end
