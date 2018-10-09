# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

running = true

timeouts = [0.1, 0.3, 0.6, 0.7, 1]

module Enumerable
  def async_each(&block)
    each { |o| Nuclear.async { block.(o) } }
  end
end

timeouts.async_each do |t|
  Nuclear.await Nuclear.sleep(t)
  puts "slept #{t}s"
end
