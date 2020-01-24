# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

sleep 0

f1 = spin {
  puts "say something"
  # sleep 0.1
  v = gets
  puts "you said #{v}"
}

# f2 = spin {
#   sleep 0.2
# }

$start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)



trace = TracePoint.new(:line, :call, :return, :c_call, :c_return, :b_call, :b_return, :fiber_switch) do |tp|
  # next if tp.path =~ /^#{Exception::POLYPHONY_DIR}/
  next unless Fiber.current == f1

  r = {
    stamp: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - $start_stamp,
    event: tp.event,
    fiber: Fiber.current,
    lineno: tp.lineno,
    method_id: tp.method_id,
    file: tp.path,
    parameters: (tp.event == :call || tp.event == :c_call || tp.event == :b_call) && tp.parameters,
    return_value: (tp.event == :return || tp.event == :c_return || tp.event == :b_return) && tp.return_value,
    exception: tp.event == :exception && tp.raised_exception
  }
  STDOUT.puts "#{r[:stamp]} #{r[:event]} #{r[:file]}:#{r[:lineno]} #{r[:method_id]}"
rescue => e
  p e
  exit!
end

trace.enable

suspend