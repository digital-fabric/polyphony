# frozen_string_literal: true

require 'modulation'
require 'json'

Server = import('../../lib/nuclear/http/server')

server = Server.new do |request, response|
  response.write_head(200, 'Content-Type': 'application/json')
  response.finish(request.to_json)
end

server.listen(port: 1234)
puts "listening on port 1234"