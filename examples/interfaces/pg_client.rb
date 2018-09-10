# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')
Postgres =  import('../../lib/nuclear/interfaces/postgres')

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

DB = Postgres::Connection.new(
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
)

Nuclear.interval(1) do
  Nuclear.async do
    t0 = Time.now
    res = Nuclear.await DB.query("select 1 as test")
    puts "got #{res.ntuples} records (elapsed: #{Time.now - t0}): #{res.to_a}"
  end
end

Nuclear.interval(1, 0.5) do
  puts "* #{Time.now}"
end
