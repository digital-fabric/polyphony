# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/sequel'
require 'polyphony/adapters/postgres'

URL = ENV['SEQUEL_URL'] || 'postgres://localhost/test'

x = 10000
query_count = 0

spin do
  db = Sequel.connect(URL)
  x.times { query_count += 1; db.execute('select 1 as test') }
end

spin do
  db = Sequel.connect(URL)
  x.times { query_count += 1; db.execute('select 2 as test') }
end

t0 = Time.now
Fiber.current.await_all_children
puts "query rate: #{query_count / (Time.now - t0)} reqs/s; count = #{query_count}"
