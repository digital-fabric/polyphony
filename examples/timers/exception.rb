# frozen_string_literal: true
require 'modulation'

Core = import('../../lib/nuclear/core')

Core::Reactor.interval(1) { raise "hi!"}