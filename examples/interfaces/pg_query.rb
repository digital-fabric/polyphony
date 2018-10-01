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

def perform(error)
  puts "*" * 40
  DB.transaction do
    res = Nuclear.await DB.query("select 1 as test")
    puts "result: #{res.to_a}"
    raise 'hello' if error
    DB.transaction do
      res = Nuclear.await DB.query("select 2 as test")
      puts "result: #{res.to_a}"
    end
  end
rescue => e
  puts "error: #{e.inspect}"
end

Nuclear.async do
  perform(true)
  perform(false)
  exit
end
