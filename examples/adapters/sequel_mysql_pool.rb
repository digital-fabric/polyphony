# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/sequel'
require 'polyphony/adapters/mysql2'

CONCURRENCY = ARGV.first ? ARGV.first.to_i : 1000
puts "concurrency: #{CONCURRENCY}"

db = Sequel.connect(
  'mysql2://localhost/test',
  max_connections: 100,
  preconnect: true
)

t0 = Time.now
count = 0

fibers = Array.new(CONCURRENCY) do
  spin do
    loop do
      db.execute('select sleep(0.001) as test')
      count += 1
    end
  end
end

sleep 0.1
fibers.first.terminate # Interrupt mid-query

sleep 2
puts "query rate: #{count / (Time.now - t0)} reqs/s"
fibers.each(&:interrupt)
