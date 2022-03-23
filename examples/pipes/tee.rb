# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

chunk_size = 1 << 16
file_path = ARGV[0]

File.open(file_path, 'w+') do |f|
  loop do
    len = IO.tee(STDIN, STDOUT, chunk_size)
    break if len == 0
    IO.splice(STDIN, f, len)
  end
end
