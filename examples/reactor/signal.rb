# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

Nuclear.interval(1) {
  puts Time.now
}

Nuclear.trap(:int) { EV.break; puts }