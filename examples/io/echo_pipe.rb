# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

i, o = IO.pipe

puts "Write something:"
spin {
  throttled_loop(1, count: 3) { o << STDIN.gets }
  o.close
}

while data = i.readpartial(8192)
  STDOUT << "You wrote: #{data}"
end

