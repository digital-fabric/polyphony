# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/postgres'

PGOPTS = {
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
}.freeze

DBPOOL = Polyphony::ResourcePool.new(limit: 8) { PG.connect(PGOPTS) }

def get_records(db)
  db.query('select pg_sleep(0.001) as test')
  # puts "got #{res.ntuples} records: #{res.to_a}"
rescue StandardError => e
  puts "got error: #{e.inspect}"
  puts e.backtrace.join("\n")
end

CONCURRENCY = ARGV.first ? ARGV.first.to_i : 10
puts "concurrency: #{CONCURRENCY}"

DBPOOL.preheat!
t0 = Time.now
count = 0

coprocs = CONCURRENCY.times.map do
  spin do
    loop do
      DBPOOL.acquire do |db|
        get_records(db)
        count += 1
      end
    end
  end
end
sleep 5
puts "count: #{count} query rate: #{count / (Time.now - t0)} queries/s"
coprocs.each(&:interrupt)
