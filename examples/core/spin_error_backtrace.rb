# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def error(t)
  raise "hello #{t}"
end

def deferred_error(t)
  puts "deferred_error"
  spin { de2(t) }.await
end

def de2(t)
  snooze
  error(t)
end

def spin_with_error
  spin { error(4) }
end

spin do
  spin do
    spin do
      deferred_error(3)
    end.await
  end.await
end.await

suspend
suspend