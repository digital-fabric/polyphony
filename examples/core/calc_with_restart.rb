# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

# Kernel#spin starts a new fiber
@controller = spin do
  @worker = spin do
    loop do
      # Each fiber has a mailbox for receiving messages
      peer, op, x, y = receive
      result = x.send(op, y)
      # The result is sent back to the "client"
      peer << result
    end
  end
  # The controller fiber will block until the worker is done (but notice that
  # the worker runs an infinite loop.)
  @worker.await
rescue => e
  puts "Uncaught exception in worker: #{e}. Restarting..."
  @worker.restart
end

def calc(op, x, y)
  # Send the job to the worker fiber...
  @worker << [Fiber.current, op, x, y]
  # ... and wait for the result
  receive
end

# wait for worker to start
snooze until @worker

p calc(:+, 2, 3)
p calc(:**, 2, 3)
p calc(:+, 2, nil)

# wait for the controller to terminate
@controller.await
