#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

STDIN.sync = true
STDOUT.sync = true

input = Nuclear::IO.lines(Nuclear::IO.stdin)

Nuclear.async do
  Nuclear.interval(1) { puts Time.now }

  loop do
    Nuclear::IO.stdout << "Say something: "
    l = Nuclear.await(input)
    break unless l
    Nuclear::IO.stdout << "You said: #{l}"
  end
end
