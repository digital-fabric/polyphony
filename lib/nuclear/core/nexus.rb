# frozen_string_literal: true

export_default :Nexus

FiberPool = import('./fiber_pool')

class Nexus
  def initialize(tasks = nil, &block)
    @tasks = tasks || []
    @completed = []
    @block = block
  end

  def <<(task)
    @tasks << task
  end

  def to_proc
    proc do |&block2|
      @fibers = []
      begin
        (block2 || @block)&.(self)
        @tasks.each { |t| start_sub_task(t) }
        @nexus_fiber = Fiber.current
        Fiber.yield_and_raise_error
      rescue Exception => e
        cancel(Cancelled.new(nil, nil)) unless @cancelled
        MoveOn === e ? e.value : raise(e)
      end
    end
  end

  def start_sub_task(task)
    if task.async
      task.(
        no_block: true,
        on_start: proc { |fiber| @fibers << fiber },
        on_done: proc { |fiber, result| task_completed(Fiber.current, result) }
      )
    else
      next_tick do
        FiberPool.spawn do |fiber|
          begin
            @fibers << fiber
            result = await task
            task_completed(fiber, result)
          rescue Exception => e
            puts "error: #{e}"
            task_completed(fiber, e) unless @cancelled
          end
        end
      end
    end
  end

  def cancel(error)
    @cancelled = true
    @fibers.each { |f| f.resume(error) }
  end

  def task_completed(fiber, result)
    return if @cancelled

    @fibers.delete(fiber)
    if result.is_a?(Exception)
      @nexus_fiber&.resume(result)
    elsif @fibers.size == 0
      @nexus_fiber&.resume(@tasks.size) 
    end
  end

  def move_on!(value)
    @nexus_fiber&.resume(MoveOn.new(nil, value))
  end
end
