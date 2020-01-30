# frozen_string_literal: true

require 'bundler/setup'

require_relative './coverage' if ENV['COVERAGE']

require 'polyphony'

require 'fileutils'
require_relative './eg'

require 'minitest/autorun'
require 'minitest/reporters'

::Exception.__disable_sanitized_backtrace__ = true

Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new
]

class MiniTest::Test
  def teardown
    # wait for any remaining scheduled work
    Thread.current.switch_fiber
    Polyphony.reset!
  end
end

module Kernel
  def capture_exception
    yield
  rescue Exception => e
    e
  end
end