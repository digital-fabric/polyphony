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
  def setup
    if Fiber.current.children.size > 0
      puts "Children left: #{Fiber.current.children.inspect}"
      exit!
    end
    Fiber.current.setup_main_fiber
    sleep 0
  end

  def teardown
    Fiber.current.terminate_all_children
    Fiber.current.await_all_children
  end
end

module Kernel
  def capture_exception
    yield
  rescue Exception => e
    e
  end
end