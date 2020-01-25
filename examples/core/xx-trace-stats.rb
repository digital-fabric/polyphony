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

$start_stamp = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

$watched_fiber = nil
debug_mode = :step

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
end

class << TracePoint
  alias_method :orig_new, :new
  def new(*args, &block)
    polyphony_file_regexp = /^#{Exception::POLYPHONY_DIR}/

    orig_new(*args) do |tp|
      next unless !$watched_fiber || Fiber.current == $watched_fiber

      if (tp.event == :c_return) && (tp.method_id == :__fiber_trace__)
        block.(FiberTracePoint.new(tp))
      else
        next if tp.path =~ polyphony_file_regexp
  
        block.(tp)
      end

      #   STDOUT.orig_puts "#{r[:stamp]} #{fiber&.tag} #{event} (#{value.inspect})"
      #   next
      # end
    end
  end
end

$records = []

trace = TracePoint.new(:line, :call, :return, :c_call, :c_return, :b_call, :b_return) do |tp|
  r = {
    stamp: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - $start_stamp,
    event: tp.event,
    fiber: tp.is_a?(FiberTracePoint) ? tp.fiber : Fiber.current,
    lineno: tp.lineno,
    method_id: tp.method_id,
    file: tp.path,
    parameters: (tp.event == :call || tp.event == :c_call || tp.event == :b_call) && tp.parameters,
    return_value: (tp.event == :return || tp.event == :c_return || tp.event == :b_return) && tp.return_value,
    exception: tp.event == :raise && tp.raised_exception
  }

  $records << r

  # if tp.event == :line
  #   source = cache[r[:file]] ||= IO.orig_read(r[:file]).lines
  #   STDOUT.orig_puts format("* %s:%d", r[:file], r[:lineno])
  #   STDOUT.orig_puts format("%04d %s", r[:lineno], source[r[:lineno] - 1])
  #   # orig_gets
  #   next
  # end
end

trace.enable

f2 = spin(:f2) { 10.times { sleep 0.1 } }

1000.times {
  spin { 10.times { sleep rand(0.05..0.15) } }
}

# $watched_fiber = f2
suspend
trace.disable
puts("record count: %d" % $records.size)

records_hash = Hash.new { |h, k| h[k] = [] }
by_fiber = $records.inject(records_hash) do |h, r|
  h[r[:fiber]] << r; h
end

puts("fiber count: %d" % by_fiber.size)
puts

by_fiber[f2].each { |r| 
# $records.each { |r| 
  case r[:event]
  when /^fiber_/
    # STDOUT.orig_puts "#{r[:stamp]} #{r[:fiber]&.tag} #{r[:event]} (#{r[:value].inspect})"
    STDOUT.orig_puts "#{r[:stamp]} #{r[:event]} (#{r[:value].inspect})"
  else
    STDOUT.orig_puts "#{r[:stamp]} #{r[:fiber]&.tag} #{r[:event]} (#{r[:value].inspect})"
  end
}

state = 0
run_wait_stamp = nil
schedule_stamp = nil
run_time = 0
wait_time = 0
schedule_count = 0
schedule_acc = 0
by_fiber[f2].each { |r|
  case r[:event]
  when :fiber_create
    state = 0
    run_wait_stamp = r[:stamp]
  when :fiber_schedule
    schedule_count += 1
    schedule_stamp = r[:stamp]
  when :fiber_run
    schedule_acc += r[:stamp] - schedule_stamp
    wait_time += r[:stamp] - run_wait_stamp
    state = 1
    schedule_stamp = run_wait_stamp = r[:stamp]
  when :fiber_switchpoint, :fiber_terminate
    run_time += r[:stamp] - run_wait_stamp
    state = 0
    run_wait_stamp = r[:stamp]
  end
}
puts(
  format(
    "f2 run: %f wait: %f schedule_count: %d avg schedule latency: %f",
    run_time,
    wait_time,
    schedule_count,
    schedule_acc / schedule_count
  )
)
