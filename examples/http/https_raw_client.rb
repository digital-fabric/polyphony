# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

t0 = Time.now
io = Polyphony::Net.tcp_connect('google.com', 443, secure: true)
io.write("GET / HTTP/1.0\r\nHost: realiteq.net\r\n\r\n")
reply = io.read
puts "time: #{Time.now - t0}"
puts
puts reply
