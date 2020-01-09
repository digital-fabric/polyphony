# frozen_string_literal: true

require 'fiber'
require 'timeout'
require 'open3'

Exceptions  = import('../core/exceptions')

# Exeption overrides
class ::Exception
  class << self
    attr_accessor :__disable_sanitized_backtrace__
  end

  alias_method :orig_initialize, :initialize

  def initialize(*args)
    @__raising_fiber__ = Fiber.current
    orig_initialize(*args)
  end

  alias_method_once :orig_backtrace, :backtrace
  def backtrace
    unless @first_backtrace_call
      @first_backtrace_call = true
      return orig_backtrace
    end

    if @__raising_fiber__
      backtrace = orig_backtrace || []
      sanitize(backtrace + @__raising_fiber__.caller)
    else
      sanitize(orig_backtrace)
    end
  end

  POLYPHONY_DIR = File.expand_path(File.join(__dir__, '..'))

  def sanitize(backtrace)
    return backtrace if ::Exception.__disable_sanitized_backtrace__

    backtrace.reject { |l| l[POLYPHONY_DIR] }
  end
end

# Overrides for Process
module ::Process
  def self.detach(pid)
    fiber = spin { Gyro::Child.new(pid).await }
    fiber.define_singleton_method(:pid) { pid }
    fiber
  end
end

# Kernel extensions (methods available to all objects / call sites)
module ::Kernel
  alias_method :orig_sleep, :sleep

  alias_method :orig_backtick, :`
  def `(cmd)
    # $stdout.orig_puts '*' * 60
    # $stdout.orig_puts caller.join("\n")
    Open3.popen3(cmd) do |i, o, e, _t|
      i.close
      while (l = e.readpartial(8192))
        $stderr << l
      end
      o.read
    end
  end

  ARGV_GETS_LOOP = proc do |calling_fiber|
    ARGV.each do |fn|
      File.open(fn, 'r') do |f|
        while (line = f.gets)
          calling_fiber = calling_fiber.transfer(line)
        end
      end
    end
  rescue Exception => e
    calling_fiber.transfer(e)
  end

  alias_method :orig_gets, :gets
  def gets(*_args)
    return $stdin.gets if ARGV.empty?

    @gets_fiber ||= Fiber.new(&ARGV_GETS_LOOP)
    return @gets_fiber.safe_transfer(Fiber.current) if @gets_fiber.alive?

    nil
  end

  alias_method :orig_system, :system
  def system(*args)
    Open3.popen2(*args) do |i, o, _t|
      i.close
      while (l = o.readpartial(8192))
        $stdout << l
      end
    end
    true
  rescue SystemCallError
    nil
  end
end

# Override Timeout to use cancel scope
module ::Timeout
  def self.timeout(sec, klass = nil, message = nil, &block)
    cancel_after(sec, &block)
  rescue Exceptions::Cancel => e
    error = klass ? klass.new(message) : ::Timeout::Error.new
    error.set_backtrace(e.backtrace)
    raise error
  end
end
