# frozen_string_literal: true

require 'modulation'
require 'json'
require 'localhost/authority'
require 'time'

Server = import('../../lib/rubato/http/server')

H_SERVER = 'Server'
H_DATE = 'Date'

SERVER_NAME = 'rubato/0.6'
HELLO_WORLD = 'Hello World'

server = Server.new do |request, response|
  response.write_head(200, 
    H_SERVER => SERVER_NAME, H_DATE => Time.now.httpdate)
  response.finish(HELLO_WORLD)
end

authority = Localhost::Authority.fetch
server.listen(host: 'localhost', port: 1234, secure_context: authority.server_context)
puts "listening on port 1234"