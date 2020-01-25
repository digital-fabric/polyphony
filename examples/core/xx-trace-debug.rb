# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

sleep 0

f1 = spin(:f1) {
  puts "* write something..."
  sleep 0.1
  v = gets
  puts "* you wrote #{v}"
}

f2 = spin(:f2) {
  p :sleeping
  sleep 1
  p :wokeup
}

$start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

watcher_fiber = nil
debug_mode = :step

cache = {}

trace = TracePoint.new(:line, :call, :return, :c_call, :c_return, :b_call, :b_return, :fiber_switch) do |tp|

  next if tp.path =~ /^#{Exception::POLYPHONY_DIR}/
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
    orig_gets
    next
  end

  if (tp.event =~ /return/) && (r[:method_id] =~ /^__trace_(.+)__/)
    event = $1.to_sym
    fiber = r[:return_value][0]
    value = r[:return_value][1]
    STDOUT.orig_puts "#{r[:stamp]} #{fiber&.tag} #{event} (#{value.inspect})"
    next
  end

  # STDOUT.orig_puts "#{r[:stamp]} #{r[:event]} #{r[:file]}:#{r[:lineno]} #{r[:method_id]}"
  
  # STDOUT.orig_puts "#{r[:file]}:#{r[:lineno]} #{r[:event]} (#{r[:fiber]})"
  # STDOUT.orig_puts "(continue),("
end

trace.enable
p 1
suspend
p 2