# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true


sleep 0
$records = []

Gyro.trace(true)
trace = Polyphony::Trace.new { |r| $records << r }
trace.enable

f2 = spin(:f2) { 3.times { sleep 0.1 } }

10.times {
  spin { 3.times { sleep rand(0.05..0.15) } }
}

suspend
trace.disable
puts("record count: %d" % $records.size)

analysis = Polyphony::Trace.analyze $records

puts("fiber count: %d" % analysis[:by_fiber].size)
puts

worker_fibers = analysis[:by_fiber].keys - [Fiber.current]

analysis[:by_fiber][f2].each { |r| 
  case r[:event]
  when /^fiber_/
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
worker_fibers.each do |f|
  analysis[:by_fiber][f].each { |r|
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
end

puts(
  format(
    "f2 run: %f wait: %f schedule_count: %d avg schedule latency: %f",
    run_time,
    wait_time,
    schedule_count,
    schedule_acc / schedule_count
  )
)
