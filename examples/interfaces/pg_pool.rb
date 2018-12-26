# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Postgres =  import('../../lib/rubato/extensions/postgres')

PGOPTS = {
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
}

DBPOOL = Rubato::ResourcePool.new(limit: 8) { PG.connect(PGOPTS) }

def get_records(db)
  res = db.query("select pg_sleep(0.0001) as test")
  # puts "got #{res.ntuples} records: #{res.to_a}"
rescue => e
  puts "got error: #{e.inspect}"
  puts e.backtrace.join("\n")
end

CONCURRENCY = 10

spawn do
  DBPOOL.preheat!
  t0 = Time.now
  count = 0
  coprocs = CONCURRENCY.times.map {
    spawn { loop { DBPOOL.acquire { |db| get_records(db); count += 1 } } }
  }
  sleep 3
  puts "count: #{count} query rate: #{count / (Time.now - t0)} queries/s"
  coprocs.each(&:interrupt)
end

# spawn do
#   $db = PG.connect(
#     host:     '/tmp',
#     user:     'reality',
#     password: nil,
#     dbname:   'reality',
#     sslmode:  'require'
#   )
  
#   t0 = Time.now
#   10000.times { get_records }
#   puts "query rate: #{10000 / (Time.now - t0)} reqs/s"

#   # get_records
# end

# every(1) do
#   spawn { get_records }
# end
