# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

::Exception.__disable_sanitized_backtrace__ = true

def test
  # error is propagated to calling coprocess
  raised_error = nil
  spin do
    spin do
      raise 'foo'
    end
    puts "before snooze"
    snooze # allow nested coprocess to run before finishing
    puts "after snooze"
  end
  suspend
rescue Exception => e
  raised_error = e
ensure
  puts "raised_error: #{raised_error.inspect}"
  # puts "msg: #{raised_error.message.inspect}"
end

test
begin
  puts "last suspend"
  #suspend
  Gyro.run
rescue => e
  puts "!" * 60
  puts "Error after last suspend: #{e.inspect}"
end