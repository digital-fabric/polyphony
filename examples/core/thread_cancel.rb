# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Nuclear     = import('../../lib/nuclear')

hey = nil

def lengthy_op
  acc = 0
  count = 0
  100.times { acc += IO.read('../../docs/reality-ui.bmpr').bytesize; count += 1; p count }
  acc / count
end

async! do
  begin
    t0 = Time.now
    cancel_after(0.01) do
      data = await Nuclear::Thread.spawn { lengthy_op }
      puts "read #{data.bytesize} bytes (#{Time.now - t0}s)"
    end
  rescue Exception => e
    puts "error: #{e}"
  end
  p hey
end

