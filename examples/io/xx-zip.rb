# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'zlib'

i, o = IO.pipe

w = Zlib::GzipWriter.new(o)

s = (1..1000).map { (65 + rand(26)).chr }.join
puts "full length: #{s.bytesize}"
w << s
w.close
o.close


z = i.read
puts "zipped length: #{z.bytesize}"
