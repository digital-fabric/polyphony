#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'
require 'json'

HTTP = import('../../lib/nuclear/http')

body = 'Hello, world!'
reply = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"

server = HTTP::Server.new do |socket, req|
  # body
  # object = {
  #   url: req.request_url,
  #   headers: req.headers,
  #   upgrade: req.upgrade_data
  # }
  # body = object.to_json

  reply = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"

  socket << reply
end

server.listen(port: 1234)
puts "listening on port 1234"