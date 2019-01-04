# frozen_string_literal: true

require 'modulation'
Polyphony = import('../../lib/polyphony')

async def try_connect(supervisor, target)
  puts "trying #{target[2]}"
  socket = Polyphony::Net.tcp_connect(target[2], 80)
  supervisor.stop!([target[2], socket])
rescue IOError, SystemCallError
end

def happy_eyeballs(hostname, port, max_wait_time: 0.025)
  targets = Socket.getaddrinfo(hostname, port, :INET, :STREAM)
  t0 = Time.now
  cancel_after(5) do
    success = supervise do |supervisor|
      targets.each_with_index do |t, idx|
        sleep(max_wait_time) if idx > 0
        supervisor.spawn try_connect(supervisor, t)
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
happy_eyeballs("debian.org", "https")
