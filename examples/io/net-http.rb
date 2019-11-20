# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'net/http'

uri = URI('http://realiteq.net/?q=time')

begin
  puts Net::HTTP.get(uri)
rescue StandardError => e
  p e
  puts '*' * 40
  puts e.backtrace[0..4].join("\n")
end
