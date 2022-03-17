# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

require 'polyphony'

IO.http1_splice_chunked(STDIN, STDOUT, 16384)
