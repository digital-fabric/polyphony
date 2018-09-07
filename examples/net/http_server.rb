#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'
require 'json'

HTTP = import('../../lib/nuclear/http')

server = HTTP::Server.new do |request, response|
  response.write_head(200, 'Content-Type': 'application/json')
  response.finish(request.inspect)
end

server.listen(port: 1234)
puts "listening on port 1234"