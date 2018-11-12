# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def connect(host, port)
  socket = ::Socket.new(:INET, :STREAM)
  Nuclear::IO::SocketWrapper.new(socket).tap do |o|
    await sleep(rand * 0.5)
    await o.connect(host, port)
  end
end

async def try_connect(supervisor, target)
  socket = await connect(target[2], 80)
  supervisor.stop!([target[2], socket])
rescue => e
  puts "#try_connect exception (#{target[2]}): #{e}"
  # raise e
end

def getaddrinfo(host, port)
  Nuclear::ThreadPool.process { Socket.getaddrinfo(host, port, :INET, :STREAM) }
end

async def open_tcp_socket(hostname, port, max_wait_time: 0.25)
  targets = await getaddrinfo(hostname, port)
  success = await supervise do |supervisor|
    last_target = nil
    targets.each do |t|
      await sleep max_wait_time if last_target
      puts "spawn #{t[2]}"
      supervisor << try_connect(supervisor, t)
      last_target = t
    end
  end
  puts "success: #{success[0]} #{success[1]}"
end

# Let's try it out:
spawn open_tcp_socket("debian.org", "https")
