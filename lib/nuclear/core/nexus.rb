# frozen_string_literal: true

export_default :Nexus

Task = import('./task')

class Nexus
  def initialize(tasks = nil, &block)
    @tasks = tasks || []
    @completed = []
    @block = block
  end

  def <<(task)
    @tasks << task
  end

  def cancel(error)
    @cancelled = true
    @fibers.each { |f| f.resume(error) }
  end

  def task_completed(fiber, error)
    @fibers.delete(fiber)
    if error
      @nexus_fiber.resume(error)
    elsif @fibers.size == 0
      @nexus_fiber.resume(@tasks.size) 
    end
  end

  def to_proc
    @fibers = []
 
    proc do |&block2|
      @nexus_fiber = Fiber.current
      begin
        (block2 || @block)&.(self)
        @tasks.each do |t|
          EV::Timer.new(0, 0) do
            async! do
              begin
                fiber = Fiber.current
                @fibers << fiber
                result = await t
                task_completed(fiber, nil)
              rescue Exception => e
                task_completed(fiber, e) unless @cancelled
              end
            end
          end
        end
        Fiber.yield_and_raise_error
      rescue Exception => e
        cancel(Cancelled.new(nil, nil)) unless @cancelled
        MoveOn === e ? e.value : raise(e)
      end
    end
  end

  def move_on!(value)
    @nexus_fiber.resume(MoveOn.new(nil, value))
  end
end
