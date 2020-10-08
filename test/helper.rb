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

class ::Fiber
  attr_writer :auto_watcher
end

module ::Kernel
  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.first.is_a?(String)
      if args.size > 1
        format("%s: %p\n", args.shift, args)
      else
        format("%s\n", args.first)
      end
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end
end

class MiniTest::Test
  def setup
    # trace "* setup #{self.name}"
    if Fiber.current.children.size > 0
      puts "Children left: #{Fiber.current.children.inspect}"
      exit!
    end
    Fiber.current.setup_main_fiber
    Fiber.current.instance_variable_set(:@auto_watcher, nil)
    Thread.current.backend.finalize
    Thread.current.backend = Polyphony::Backend.new
    sleep 0
  end

  def teardown
    # trace "* teardown #{self.name}"
    Fiber.current.terminate_all_children
    Fiber.current.await_all_children
    Fiber.current.instance_variable_set(:@auto_watcher, nil)
  rescue => e
    puts e
    puts e.backtrace.join("\n")
    exit!
  end

  def fiber_tree(fiber)
    { fiber: fiber, children: fiber.children.map { |f| fiber_tree(f) } }
  end
end

module Kernel
  def capture_exception
    yield
  rescue Exception => e
    e
  end
end

module Minitest::Assertions
  def assert_in_range exp_range, act
    msg = message(msg) { "Expected #{mu_pp(act)} to be in range #{mu_pp(exp_range)}" }
    assert exp_range.include?(act), msg
  end
end

puts "Polyphony backend: #{Thread.current.backend.kind}"