# frozen_string_literal: true

export_default :Supervisor

import '../extensions/fiber'
Exceptions = import './exceptions'

# Implements a supervision mechanism for controlling multiple fibers
class Supervisor
  def initialize
    @fibers = []
    @pending = {}
  end

  def await(&block)
    @mode = :await
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
    @fibers.map(&:result)
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    finalize_await
  end
  alias_method :join, :await

  def select(&block)
    @mode = :select
    @select_fiber = nil
    @supervisor_fiber = Fiber.current
    block&.(self)
    suspend
    [@select_fiber.result, @select_fiber]
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    finalize_select
  end

  def finalize_await
    if still_running?
      stop_all_tasks
      suspend
    else
      @supervisor_fiber = nil
    end
  end

  def finalize_select
    stop_all_tasks if still_running?
    @supervisor_fiber = nil
  end

  def spin(orig_caller = caller, &block)
    add Fiber.spin(orig_caller, &block)
  end

  def add(fiber)
    @fibers << fiber
    @pending[fiber] = true
    fiber.when_done { task_completed(fiber) }
    fiber
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

  def task_completed(fiber)
    return unless @pending[fiber]

    @pending.delete(fiber)
    return unless @pending.empty? || (@mode == :select && !@select_fiber)

    @select_fiber = fiber if @mode == :select
    @supervisor_fiber&.schedule
  end
end

# Supervision extensions for Fiber class
class ::Fiber
  class << self
    def await(*fibers)
      supervisor = Supervisor.new
      fibers.each { |f| supervisor << f }
      supervisor.await
    end
    alias_method :join, :await

    def select(*fibers)
      supervisor = Supervisor.new
      fibers.each { |f| supervisor << f }
      supervisor.select
    end
  end
end
