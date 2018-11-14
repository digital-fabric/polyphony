# frozen_string_literal: true

require_relative '../core/rubato'
require_relative '../core/rubato_io'

def connect(host, port)
  proc do
    socket = ::Socket.new(:INET, :STREAM)
    SocketWrapper.new(socket).tap do |o|
      # await sleep(rand * 0.5)
      await o.connect(host, port)
    end
  end
end

def try_connect(supervisor, target)
  proc do
    puts "try_connect #{target[2]}"
    t0 = Time.now
    socket = await connect(target[2], 80)
    puts "connected to #{target[2]} (#{Time.now - t0}s)"
    supervisor.stop!([target[2], socket])
  rescue => e
    puts "#try_connect error (#{target[2]}): #{e}"
    # raise e
  rescue Exception => e
    puts "#try_connect exception (#{target[2]}): #{e}"
    raise e
  end
end

def getaddrinfo(host, port)
  # Nuclear::ThreadPool.process { Socket.getaddrinfo(host, port, :INET, :STREAM) }
  proc do
    Socket.getaddrinfo(host, port, :INET, :STREAM)
  end
end

def open_tcp_socket(hostname, port, max_wait_time: 0.25)
  proc do
    targets = await getaddrinfo(hostname, port)
    puts "*" * 40
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
end

# Let's try it out:
spawn open_tcp_socket("debian.org", "https")
