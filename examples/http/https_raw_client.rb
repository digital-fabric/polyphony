# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

t0 = Time.now
io = Polyphony::Net.tcp_connect('realiteq.net', 443, secure: true)
io.write("GET /?q=time HTTP/1.0\r\nHost: realiteq.net\r\n\r\n")
reply = io.read
puts "time: #{Time.now - t0}"
puts
puts reply