# frozen_string_literal: true

# Exeption overrides
class ::Exception
  class << self
    attr_accessor :__disable_sanitized_backtrace__
  end

  attr_accessor :source_fiber, :raising_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args)
    @raising_fiber = Fiber.current
    orig_initialize(*args)
  end

  alias_method :orig_backtrace, :backtrace
  def backtrace
    unless @backtrace_called
      @backtrace_called = true
      return orig_backtrace
    end

    sanitized_backtrace
  end

  def sanitized_backtrace
    return sanitize(orig_backtrace) unless @raising_fiber

    backtrace = orig_backtrace || []
    sanitize(backtrace + @raising_fiber.caller)
  end

  POLYPHONY_DIR = File.expand_path(File.join(__dir__, '..'))

  def sanitize(backtrace)
    return backtrace if ::Exception.__disable_sanitized_backtrace__

    backtrace.reject { |l| l[POLYPHONY_DIR] }
  end

  def invoke
    Kernel.raise(self)
  end
end
