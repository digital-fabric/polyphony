# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

PORT = 9090

server = TCPServer.open('127.0.0.1', PORT)
puts "pid #{Process.pid} Polyphony (#{Thread.current.backend.kind}) listening on port #{PORT}"

# spin_loop(interval: 1) do
#   p Thread.current.fiber_scheduling_stats
# end

@max = 0
@count = 0

def handle_close(client)
  t0 = monotonic_clock_time
  spin do
    client.recv(1024)
    t1 = monotonic_clock_time
    client.send("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n",0)

    elapsed = t1 - t0
    @max = elapsed if elapsed > @max
    @count += 1
    if @count % 1000 == 0
      puts "max send latency: #{@max}"
    end
    client.close
  end
end

def monotonic_clock_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

max = 0
t0 = monotonic_clock_time
count = 0
while (client = server.accept)
  t1 = monotonic_clock_time
  elapsed = t1 - t0
  max = elapsed if elapsed > max
  count += 1
  if count % 1000 == 0
    puts "max accept latency: #{@max}"
  end
  handle_close(client)
end
  
# server.accept_loop do |client|
#   spin do
#     loop do
#       client.recv(1024)
#       client.send("HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\nHello, world!\n",0)
#     end
#   rescue SystemCallError
#     # ignore
#   end
# end
