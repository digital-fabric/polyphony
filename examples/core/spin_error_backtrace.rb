# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

def error(t)
  raise "hello #{t}"
end

def deferred_error(t)
  snooze
  de2(t)
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
