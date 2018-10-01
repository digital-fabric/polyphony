# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')
Postgres =  import('../../lib/nuclear/interfaces/postgres')

DB = Postgres::Client.new(
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
)

def get_records
  res = Nuclear.await DB.query("select 1 as test")
  puts "got #{res.ntuples} records: #{res.to_a}"
rescue => e
  puts "got error: #{e.inspect}"
end

Nuclear.async { get_records }

Nuclear.interval(1) do
  Nuclear.async { get_records }
end
