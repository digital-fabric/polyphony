# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

buffer = +''
socket = TCPSocket.new('google.com', 80)
socket.send("GET /?q=time HTTP/1.1\r\nHost: google.com\r\n\r\n", 0)
move_on_after(5) {
  while (data = socket.readpartial(8192))
    buffer << data
  end
}

puts "*" * 40
p buffer