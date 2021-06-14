# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

queue = Queue.new

4.times { |i|
  spin_loop {
    job = queue.pop
    puts("worker %d job %s" % [i, job.inspect])
  }
}

(1..10).each do |i|
  queue << "job#{i}"
end

sleep 0.1 until queue.empty?
