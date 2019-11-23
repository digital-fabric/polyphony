# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

i, o = IO.pipe

puts 'Say something:'
spin do
  loop { o << STDIN.gets }
  o.close
end

while (data = i.readpartial(8192))
  STDOUT << "You said: #{data}"
end
