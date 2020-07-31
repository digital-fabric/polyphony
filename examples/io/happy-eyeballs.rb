# frozen_string_literal: true

require 'polyphony'

def try_connect(ip_address, port, supervisor)
  puts "trying #{ip_address}"
  sleep rand * 0.2
  socket = TCPSocket.new(ip_address, port)
  puts "connected to #{ip_address}"
  supervisor.schedule [ip_address, socket]
rescue IOError, SystemCallError
  # ignore error
end

def happy_eyeballs(hostname, port, max_wait_time: 0.010)
  targets = Socket.getaddrinfo(hostname, port, :INET, :STREAM)
  t0 = Time.now
  fibers = []
  supervisor = Fiber.current
  spin do
    targets.each do |t|
      spin { try_connect(t[2], t[1], supervisor) }
      sleep(max_wait_time)
    end
    suspend
  end
  target, socket = move_on_after(5) { suspend }
  supervisor.shutdown_all_children
  if target
    puts format('success: %s (%.3fs)', target, Time.now - t0)
  else
    puts 'timed out'
  end
end

happy_eyeballs('debian.org', 'https')
