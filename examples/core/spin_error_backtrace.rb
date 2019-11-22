# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/extensions/backtrace'

def error(t)
  raise "hello #{t}"
end

def spin_with_error
  spin { error(4) }
end

# begin
#   error(1)
# rescue => e
#   puts "error: #{e.inspect}"
#   puts "backtrace:"
#   puts e.backtrace.join("\n")
#   puts
# end

# begin
#   spin do
#     error(2)
#   end.await
# rescue => e
#   puts "error: #{e.inspect}"
#   puts "backtrace:"
#   puts e.backtrace.join("\n")
#   puts
# end

begin
  puts "main fiber: #{Fiber.current.inspect}"
  spin do
    spin do
      spin do
        error(3)
      end.await
    end.await
  end.await
rescue StandardError => e
  puts "error: #{e.inspect}"
  puts 'backtrace:'
  puts e.backtrace.join("\n")
  puts
end

# spin_with_error
