# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

# trap('TERM') do
#   Polyphony.emit_signal_exception(::SystemExit)
# end

# trap('INT') do
#   Polyphony.emit_signal_exception(::Interrupt)
# end

puts "go to sleep"
begin
  sleep
ensure
  puts "done sleeping"
end
