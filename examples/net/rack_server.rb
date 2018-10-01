# frozen_string_literal: true

require 'modulation'
require 'json'
require 'time'

Rack = import('../../lib/nuclear/http/rack')

server = Rack.load_app(File.expand_path('./config.ru', __dir__))

server.listen(port: 1234)
puts "listening on port 1234"