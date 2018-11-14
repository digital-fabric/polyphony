# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Rubato     = import('../../lib/rubato')

def lengthy_op
  IO.read('../../docs/reality-ui.bmpr')
end

spawn do
  data = await Rubato::Thread.spawn { lengthy_op }
  puts "read #{data.bytesize} bytes"
end
