# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/adapters/postgres'

opts = {
  host:     '/tmp',
  user:     'reality',
  password: nil,
  dbname:   'reality',
  sslmode:  'require'
}

db1 = PG.connect(opts)
db2 = PG.connect(opts)

spin_loop {
  STDOUT << '.'
  sleep 0.1
}

db1.query('listen foo')
spin_loop {
  db1.wait_for_notify(1) { |channel, _, msg| puts "\n#{msg}" }
  STDOUT << '?'
}

spin_loop {
  sql = format("notify foo, %s", db2.escape_literal(Time.now.to_s))
  db2.query(sql)
  STDOUT << '!'
  sleep rand(1.5..3)
}

suspend