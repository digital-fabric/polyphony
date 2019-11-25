# frozen_string_literal: true

# idea taken from the example given in trio:
# https://www.youtube.com/watch?v=oLkfnc_UMcE

require 'bundler/setup'
require 'polyphony/http'

def try_connect(target, supervisor)
  puts "trying #{target[2]}"
  socket = Polyphony::Net.tcp_connect(target[2], 80)
  # connection successful
  supervisor.stop!([target[2], socket])
rescue IOError, SystemCallError
  # ignore error
end

def happy_eyeballs(hostname, port, max_wait_time: 0.025)
  targets = Socket.getaddrinfo(hostname, port, :INET, :STREAM)
  t0 = Time.now
  cancel_after(5) do
    success = supervise do |supervisor|
      targets.each_with_index do |t, idx|
        sleep(max_wait_time) if idx > 0
        supervisor.spin { try_connect(t, supervisor) }
      end
    end
    if success
      puts format('success: %s (%.3fs)', success[0], Time.now - t0)
    else
      puts "timed out (#{Time.now - t0}s)"
    end
  end
end

# Let's try it out:
happy_eyeballs('debian.org', 'https')
