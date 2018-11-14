# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Postgres =  import('../../lib/rubato/interfaces/postgres')

DB = Postgres::Client.new(
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
)

def get_records
  res = Rubato.await DB.query("select 1 as test")
  puts "got #{res.ntuples} records: #{res.to_a}"
rescue => e
  puts "got error: #{e.inspect}"
  puts e.backtrace.join("\n")
end

Rubato.async { get_records }

Rubato.interval(1) do
  Rubato.async { get_records }
end
