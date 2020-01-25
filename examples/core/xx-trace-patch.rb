# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

sleep 0

# f1 = spin(:f1) {
#   puts "* write something..."
#   sleep 0.1
#   v = gets
#   puts "* you wrote #{v}"
# }

f2 = spin(:f2) {
  p :sleeping
  sleep 1
  p :wokeup
}

$start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

$watched_fiber = Fiber.current
debug_mode = :step

class << TracePoint
  alias_method :orig_new, :new
  def new(*args, &block)
    polyphony_file_regexp = /^#{Exception::POLYPHONY_DIR}/

    orig_new(*args) do |tp|
      next unless Fiber.current == $watched_fiber
      next if tp.path =~ polyphony_file_regexp

      if (tp.event =~ /return/) && (tp.method_id =~ /^__trace_(.+)__/)
        event = $1.to_sym
        block.(FiberTracePoint.new(tp, event))
      else
        block.(tp)
      end

      #   STDOUT.orig_puts "#{r[:stamp]} #{fiber&.tag} #{event} (#{value.inspect})"
      #   next
      # end
    end
  end

  class FiberTracePoint
    attr_reader :event, :fiber, :value

    def initialize(tp, event)
      @tp = tp
      @event = event
      @fiber = tp.return_value[0]
      @value = tp.return_value[1]
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
  end
end

cache = {}
trace = TracePoint.new(:line, :call, :return, :c_call, :c_return, :b_call, :b_return, :fiber_switch) do |tp|

  # next unless Fiber.current == f1

  r = {
    stamp: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - $start_stamp,
    event: tp.event,
    fiber: Fiber.current,
    lineno: tp.lineno,
    method_id: tp.method_id,
    file: tp.path,
    # receiver: tp.binding&.receiver,
    parameters: (tp.event == :call || tp.event == :c_call || tp.event == :b_call) && tp.parameters,
    return_value: (tp.event == :return || tp.event == :c_return || tp.event == :b_return) && tp.return_value,
    exception: tp.event == :raise && tp.raised_exception
  }

  if tp.event == :line
    source = cache[r[:file]] ||= IO.orig_read(r[:file]).lines
    STDOUT.orig_puts format("* %s:%d", r[:file], r[:lineno])
    STDOUT.orig_puts format("%04d %s", r[:lineno], source[r[:lineno] - 1])
    # orig_gets
    next
  end
end

trace.enable
$watched_fiber = f2
p 1
suspend
p 2