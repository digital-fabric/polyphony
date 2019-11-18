# frozen_string_literal: true

require 'fiber'

# This is an experiment to see if we could provide better backtraces for
# exceptions raised in fibers. Our approach is to monkey-patch Fiber.new so as
# to keep track of the caller stack trace and calling fiber. We also
# monkey-patch Exception#backtrace to calculate the full backtrace based on the
# fiber in which the exception was raised. The benefit of this approach is that
# there's no need to sanitize the backtrace (remove stack frames related to the
# backtrace calculation).
class Fiber
  attr_writer :__calling_fiber__, :__caller__

  class << self
    alias_method :orig_new, :new
    def new(&block)
      calling_fiber = Fiber.current
      fiber_caller = caller
      orig_new(&block).tap do |f|
        f.__calling_fiber__ = calling_fiber
        f.__caller__ = fiber_caller
      end
    end
  end

  def caller
    @__caller__ ||= []
    if @__calling_fiber__
      @__caller__ + @__calling_fiber__.caller
    else
      @__caller__
    end
  end
end

class Exception
  alias_method :orig_initialize, :initialize

  def initialize(*args)
    @__raising_fiber__ = Fiber.current
    orig_initialize(*args)
  end

  alias_method :orig_backtrace, :backtrace
  def backtrace
    unless @backtrace_called
      @backtrace_called = true
      return orig_backtrace
    end
    
    if @__raising_fiber__
      backtrace = orig_backtrace || []
      backtrace + @__raising_fiber__.caller
    else
      orig_backtrace
    end
  end
end

def foo
  Fiber.new do
    bar
  end.resume
end

def bar
  Fiber.new do
    raise 'baz'
  end.resume
end

foo
