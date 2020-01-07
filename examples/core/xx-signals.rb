# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

waiter = spin do
  puts 'Waiting for HUP'
  Polyphony.wait_for_signal('SIGHUP')
  puts 'Got HUP'
end

sleep 1
puts 'Sending HUP'
Process.kill('SIGHUP', Process.pid)

suspend