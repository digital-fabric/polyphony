# frozen_string_literal: true

require 'bundler/setup'

require 'minitest/autorun'
require 'minitest/reporters'

require 'polyphony'
require 'fileutils'

require_relative './eg'

Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new
]
