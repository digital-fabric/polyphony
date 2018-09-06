#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Core  = import('../../lib/nuclear/core')
include Core::Async

STDIN.sync = true
STDOUT.sync = true

lines = Core::IO.lines(Core::IO.stdin)

async do
  loop do
    Core::IO.stdout << "Say something: "
    l = await(lines)
    break unless l
    Core::IO.stdout << "You said: #{l}"
  end
end
