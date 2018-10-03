# frozen_string_literal: true

require 'modulation'
require 'json'
require 'time'

Nuclear = import('../../lib/nuclear')
Server = import('../../lib/nuclear/http/server')

H_SERVER = 'Server'
H_DATE = 'Date'

SERVER_NAME = 'nuclear/0.6'
HELLO_WORLD = 'Hello World'

server = Server.new do |request, response|
  response.write_head(200, 
    H_SERVER => SERVER_NAME, H_DATE => Time.now.httpdate)
  response.finish(HELLO_WORLD)
end

server.listen(port: 1234)
puts "listening on port 1234"
