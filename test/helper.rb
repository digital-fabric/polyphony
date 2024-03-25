# frozen_string_literal: true

require 'bundler/setup'

require_relative './coverage' if ENV['COVERAGE']

require 'httparty'
require 'polyphony'

require 'fileutils'
require_relative './eg'

require 'minitest/autorun'

::Exception.__disable_sanitized_backtrace__ = true

IS_LINUX = RUBY_PLATFORM =~ /linux/

module ::Kernel
  def debug(**h)
    k, v = h.first
    h.delete(k)

    rest = h.inject(+'') { |s, (k, v)| s << "  #{k}: #{v.inspect}\n" }
    STDOUT.orig_write("#{k}=>#{v} #{caller[0]}\n#{rest}")
  end

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

  def monotonic_clock
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end

module MiniTest; end

class MiniTest::Test
  def setup
    # trace "* setup #{self.name}"
    @__stamp = Time.now
    Thread.current.backend.finalize
    Thread.current.backend = Polyphony::Backend.new
    Fiber.current.setup_main_fiber
    Fiber.current.instance_variable_set(:@auto_watcher, nil)
    sleep 0.0001
  end

  def teardown
    Polyphony::ThreadPool.reset

    # trace "* teardown #{self.name} (#{@__stamp ? (Time.now - @__stamp) : '?'}s)"
    Fiber.current.shutdown_all_children
    if Fiber.current.children.size > 0
      puts "Children left after #{self.name}: #{Fiber.current.children.inspect}"
      exit!
    end
    # trace "* teardown done"
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

  def assert_join_threads(threads, message = nil)
    errs = []
    values = []
    while th = threads.shift
      begin
        values << th.value
      rescue Exception
        errs << [th, $!]
        th = nil
      end
    end
    values
  ensure
    if th&.alive?
      th.raise(Timeout::Error.new)
      th.join rescue errs << [th, $!]
    end
    if !errs.empty?
      msg = "exceptions on #{errs.length} threads:\n" +
        errs.map {|t, err|
        "#{t.inspect}:\n" +
          (err.respond_to?(:full_message) ? err.full_message(highlight: false, order: :top) : err.message)
      }.join("\n---\n")
      if message
        msg = "#{message}\n#{msg}"
      end
      raise MiniTest::Assertion, msg
    end
  end
end

puts "Polyphony backend: #{Thread.current.backend.kind}"
