#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

IO =          import('../../lib/nuclear/io')
Concurrency = import('../../lib/nuclear/concurrency')

STDIN.sync = true
STDOUT.sync = true

lines = IO.lines(IO.stdin)

Concurrency.async do
  loop do
    IO.stdout << "Say something: "
    l = Concurrency.await(lines)
    break unless l
    IO.stdout << "You said: #{l}"
  end
end
