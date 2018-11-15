# frozen_string_literal: true

require 'modulation'
Rubato = import('../../lib/rubato')

# frozen_string_literal: true

async def try_connect(supervisor, target)
  puts "try_connect #{target[2]}"
  t0 = Time.now
  socket = await Rubato::Net.tcp_connect(target[2], 80)
  puts "connected to #{target[2]} (#{Time.now - t0}s)"
  supervisor.stop!([target[2], socket])
rescue => e
  puts "#try_connect error (#{target[2]}): #{e}"
  # raise e
rescue Exception => e
  puts "stop connection to #{target[2]}"
  raise e
end

def getaddrinfo(host, port)
  Rubato::ThreadPool.process { Socket.getaddrinfo(host, port, :INET, :STREAM) }
end

async def happy_eyeballs(hostname, port, max_wait_time: 0.025)
  targets = await getaddrinfo(hostname, port)
  t0 = Time.now
  cancel_after(5) do
    success = await supervise do |supervisor|
      last_target = nil
      targets.each do |t|
        await sleep(max_wait_time) if last_target
        supervisor.spawn try_connect(supervisor, t)
        last_target = t
      end
    end
    if success
      puts "success: #{success[0]} #{success[1]} (#{Time.now - t0}s)"
    else
      puts "timed out (#{Time.now - t0}s)"
    end
  end
end

# Let's try it out:
spawn happy_eyeballs("debian.org", "https")
