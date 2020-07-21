# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/sequel'
require 'polyphony/adapters/mysql2'

time_printer = spin do
  last = Time.now
  throttled_loop(10) do
    now = Time.now
    puts now - last
    last = now
  end
end

db = Sequel.connect('mysql2://localhost/test')

x = 10_000
t0 = Time.now
x.times { db.execute('select 1 as test') }
puts "query rate: #{x / (Time.now - t0)} reqs/s"

time_printer.stop
