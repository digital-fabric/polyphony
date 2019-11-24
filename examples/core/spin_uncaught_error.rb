# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/extensions/backtrace'

def foo
  spin do
    spin do
      raise 'This is an error'
    end
  end
end

foo
