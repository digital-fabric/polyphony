# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'zlib'

r, w = IO.pipe
writer = Zlib::GzipWriter.new(w)

writer << 'chunk'
writer.flush
p pos: writer.pos
# w.close
writer.close

p r.read
