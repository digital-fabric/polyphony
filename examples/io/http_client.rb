# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  t0 = Time.now
  io = Rubato::Net.tcp_connect('encrypted.google.com', 443, secure: true)
  puts "connected"
  io.write("GET / HTTP/1.1\r\nHost: google.com\r\n\r\n")
  reply = io.read(2**16)
  puts "time: #{Time.now - t0}"
  puts
  puts reply
rescue => e
  p e
end
