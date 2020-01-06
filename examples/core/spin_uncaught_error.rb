# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def foo
  spin do
    spin do
      raise 'This is an error'
    end
  end
end

foo

suspend