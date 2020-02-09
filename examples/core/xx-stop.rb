# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

f1 = spin do
  f2 = spin { sleep 60 }
  f3 = spin { sleep 60 }
  sleep 60
ensure
  p 1
  f2.stop
  p 2
  f3.stop
  p "should reach here!"
end

sleep 0.1
f1.stop
snooze