# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Postgres =  import('../../lib/rubato/extensions/postgres')

$db = PG.connect(
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
)

def get_records
  res = $db.query("select 1 as test")
  # puts "got #{res.ntuples} records: #{res.to_a}"
rescue => e
  puts "got error: #{e.inspect}"
  puts e.backtrace.join("\n")
end

spawn do
  t0 = Time.now
  1000.times { get_records }
  puts "query rate: #{1000 / (Time.now - t0)} reqs/s"

  # get_records
end

# every(1) do
#   spawn { get_records }
# end
