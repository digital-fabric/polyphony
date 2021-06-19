# frozen_string_literal: true

require 'bundler/setup'

require 'polyphony'

GC.disable

p count: GC.count
snooze
p count_after_snooze: GC.count
sleep 0.1
p count_after_sleep: GC.count

Thread.current.backend.idle_gc_period = 60

p count: GC.count
snooze
p count_after_snooze: GC.count
sleep 0.1
p count_after_sleep: GC.count
