# frozen_string_literal: true
require 'modulation'

Core = import('../../lib/nuclear/core')
Postgres =  import('../../lib/nuclear/interfaces/postgres')

include Core::Async

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

Core::Reactor.interval(1) do
  async do
    t0 = Time.now
    res = await DB.query("select 1 as test")
    puts "got #{res.ntuples} records (elapsed: #{Time.now - t0}): #{res.to_a}"
  end
end

Core::Reactor.interval(1, 0.5) do
  puts "* #{Time.now}"
end
