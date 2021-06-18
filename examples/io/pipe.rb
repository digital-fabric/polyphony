# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

i, o = IO.pipe
f = spin { p i.read }

o << 'hello'
o.close
f.await
