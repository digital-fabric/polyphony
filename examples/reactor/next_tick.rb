# frozen_string_literal: true
require 'modulation'

Core = import('../../lib/nuclear/core')

Core::Reactor.interval(1) {
  Core::Reactor.next_tick { puts Time.now }
}