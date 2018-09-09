# frozen_string_literal: true
require 'modulation'

Nuclear = import('../../lib/nuclear')

Nuclear.interval(1) {
  Nuclear.next_tick { puts Time.now }
}