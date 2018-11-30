# frozen_string_literal: true

require 'modulation'
Rubato = import('../../lib/rubato')

async def try_connect(supervisor, target)
  puts "trying #{target[2]}"
  t0 = Time.now
  socket = Rubato::Net.tcp_connect(target[2], 80)
  supervisor.stop!([target[2], socket])
rescue IOError, SystemCallError
  # ignore I/O, system errors
end

async def happy_eyeballs(hostname, port, max_wait_time: 0.025)
  targets = Rubato::Net.getaddrinfo(hostname, port)
  t0 = Time.now
  cancel_after(5) do
    success = supervise do |supervisor|
      last_target = nil
      targets.each do |t|
        sleep(max_wait_time) if last_target
        supervisor.spawn try_connect(supervisor, t)
        last_target = t
      end
    end
    if success
      puts "success: #{success[0]} (#{Time.now - t0}s)"
    else
      puts "timed out (#{Time.now - t0}s)"
    end
  end
end

# Let's try it out:
spawn happy_eyeballs("debian.org", "https")
