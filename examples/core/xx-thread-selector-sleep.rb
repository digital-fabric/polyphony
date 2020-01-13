# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Thread.event_selector = Gyro::Selector

# Thread.current.setup_fiber_scheduling;

# p :go_to_sleep
# sleep 1
# p :wake_up

puts "*" * 60

t = Thread.new {
  Thread.current.setup_fiber_scheduling

  spin {
    p :go_to_sleep1
    sleep 1
    p :wake_up1
  }

  spin {
    p :go_to_sleep2
    sleep 2
    p :wake_up2
  }

  p :waiting
  suspend
}

t.join

at_exit {
  p :at_exit
}