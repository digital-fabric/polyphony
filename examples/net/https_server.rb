#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'
require 'json'
require 'localhost/authority'

HTTP = import('../../lib/nuclear/http')

server = HTTP::Server.new do |request, response|
  response.write_head(200, 'Content-Type': 'application/json')
  response.finish(request.inspect)
end

authority = Localhost::Authority.fetch
server.listen(host: 'localhost', port: 1234, secure_context: authority.server_context)
puts "listening on port 1234"