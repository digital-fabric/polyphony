# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

def work
  puts "creating fibers..."
  100000.times {
    spin {
      loop { snooze }
    }
  }

  puts "done"
  suspend
end

def work_thread
  t = Thread.new { work }
  t.join
end

main = Fiber.current
p [:main, main]

# trap('SIGINT') do
#   p [:SIGINT, Fiber.current]
#   p caller
#   exit!
# end

work