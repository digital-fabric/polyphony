# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

i, o = IO.pipe

f = spin do
  i.read_loop { |data| STDOUT << data }
end

result = nil
# File.open(__FILE__, 'r') do |f|
File.open('../tipi/log', 'r') do |f|
  result = Thread.current.backend.splice_chunks(
    f,
    o,
    "Content-Type: ruby\n\n",
    "0\r\n\r\n",
    ->(len) { "#{len.to_s(16)}\r\n" },
    "\r\n",
    16384
  )
end


o.close
f.await
p result: result
