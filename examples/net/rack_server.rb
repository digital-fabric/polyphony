# frozen_string_literal: true

require 'modulation'
require 'json'
require 'localhost/authority'
require 'time'

Rack = import('../../lib/nuclear/http/rack')

server = Rack.load_app(File.expand_path('./config.ru', __dir__))

# server.listen(port: 1234)
authority = Localhost::Authority.fetch
server.listen(host: 'localhost', port: 1234)#, secure_context: authority.server_context)
puts "listening on port 1234"
