# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
::Exception.__disable_sanitized_backtrace__ = true

50.times { STDOUT.write "hi\n" }
50.times { puts "hi" }
