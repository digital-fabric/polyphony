# frozen_string_literal: true

export :new, :analyze

require 'polyphony'

def new
  start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  ::TracePoint.new(:line, :call, :return, :c_call, :c_return, :b_call, :b_return) do |tp|
    r = {
      self: tp.self,
      binding: tp.binding,
      stamp: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_stamp,
      event: tp.event,
      fiber: tp.is_a?(FiberTracePoint) ? tp.fiber : Fiber.current,
      lineno: tp.lineno,
      method_id: tp.method_id,
      file: tp.path,
      parameters: (tp.event == :call || tp.event == :c_call || tp.event == :b_call) && tp.parameters,
      return_value: (tp.event == :return || tp.event == :c_return || tp.event == :b_return) && tp.return_value,
      exception: tp.event == :raise && tp.raised_exception
    }
    yield r
  end
end

def analyze(records)
  by_fiber = Hash.new { |h, f| h[f] = [] }
  records.each_with_object(by_fiber) { |r, h| h[r[:fiber]] << r }
  { by_fiber: by_fiber }
end

class FiberTracePoint
  attr_reader :event, :fiber, :value

  def initialize(tp)
    @tp = tp
    @event = tp.return_value[0]
    @fiber = tp.return_value[1]
    @value = tp.return_value[2]
  end

  def lineno
    @tp.lineno
  end

  def method_id
    @tp.method_id
  end

  def path
    @tp.path
  end

  def self
    @tp.self
  end

  def binding
    @tp.binding
  end
end

class << ::TracePoint
  alias_method :orig_new, :new
  def new(*args, &block)
    polyphony_file_regexp = /^#{::Exception::POLYPHONY_DIR}/

    orig_new(*args) do |tp|
      next unless !$watched_fiber || Fiber.current == $watched_fiber

      if tp.method_id == :__fiber_trace__
        block.(FiberTracePoint.new(tp)) if tp.event == :c_return
      else
        next if tp.path =~ polyphony_file_regexp
  
        block.(tp)
      end
    end
  end
end
