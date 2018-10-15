# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Nuclear     = import('../../lib/nuclear')

def lengthy_op
  IO.read('../../docs/reality-ui.bmpr')
end

async! do
  data = await Nuclear::Thread.spawn { lengthy_op }
  puts "read #{data.bytesize} bytes"
end
