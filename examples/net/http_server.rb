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

# cache server time for Date header (#httpdate is really expensive!)
server_time = ''
timer = EV::Timer.new(0, 1) { server_time = Time.now.httpdate }

server = Server.new do |request, response|
  response.write_head(200, H_DATE => server_time)
  response.finish(HELLO_WORLD)
end

server.listen(host: 'localhost', port: 1234)
puts "listening on port 1234"
