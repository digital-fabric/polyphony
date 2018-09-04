# frozen_string_literal: true
require 'modulation'

Reactor = import('../../lib/nuclear/reactor')

Reactor.interval(1) {
  Reactor.next_tick { puts Time.now }
}