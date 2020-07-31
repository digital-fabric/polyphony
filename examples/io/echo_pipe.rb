# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

i, o = IO.pipe

puts 'Say something:'
spin do
  loop { o << STDIN.gets }
  o.close
end

i.read_loop do |data|
  STDOUT << "You said: #{data}"
end
