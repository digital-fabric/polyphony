# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

File.open(__FILE__, 'r') do |f|
  line_number = 1
  while (l = f.gets)
    puts format('%03d %s', line_number, l)
    line_number += 1
  end
end
