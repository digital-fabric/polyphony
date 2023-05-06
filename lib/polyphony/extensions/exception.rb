# frozen_string_literal: true

# Extensions to the Exception class
class ::Exception
  class << self

    # Set to true to disable sanitizing the backtrace (to remove frames occuring
    # in the Polyphony code itself.)
    attr_accessor :__disable_sanitized_backtrace__
  end

  # Set to the fiber in which the exception was *originally* raised (in case the
  # exception was not caught.) The exception will propagate up the fiber tree,
  # allowing it to be caught in any of the fiber's ancestors, while the
  # `@source_fiber`` attribute will continue pointing to the original fiber.
  attr_accessor :source_fiber

  # Set to the fiber from which the exception was raised.
  attr_accessor :raising_fiber

  # @!visibility private
  alias_method :orig_initialize, :initialize

  # Initializes the exception with the given arguments.
  def initialize(*args)
    @raising_fiber = Fiber.current
    orig_initialize(*args)
  end

  # @!visibility private
  alias_method :orig_backtrace, :backtrace

  # Returns the backtrace for the exception. If
  # `Exception.__disable_sanitized_backtrace__` is not true, any stack frames
  # occuring in Polyphony's code will be removed from the backtrace.
  #
  # @return [Array<String>] backtrace
  def backtrace
    unless @backtrace_called
      @backtrace_called = true
      return orig_backtrace
    end

    sanitized_backtrace
  end

  # Raises the exception. this method is a simple wrapper to `Kernel.raise`. It
  # is overriden in the `Polyphony::Interjection` exception class.
  def invoke
    Kernel.raise(self)
  end

  private

  # Returns a sanitized backtrace for the exception.
  #
  # @return [Array<String>] sanitized backtrace
  def sanitized_backtrace
    return sanitize(orig_backtrace) unless @raising_fiber

    backtrace = orig_backtrace || []
    sanitize(backtrace + @raising_fiber.caller)
  end

  POLYPHONY_DIR = File.expand_path(File.join(__dir__, '..'))

  # Sanitizes the backtrace by removing any frames occuring in Polyphony's code
  # base.
  #
  # @param backtrace [Array<String>] unsanitized backtrace
  # @return [Array<String>] sanitized backtrace
  def sanitize(backtrace)
    return backtrace if ::Exception.__disable_sanitized_backtrace__

    backtrace.reject { |l| l[POLYPHONY_DIR] }
  end
end
