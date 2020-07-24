# frozen_string_literal: true

module Polyphony
  # Common exception class for interrupting fibers. These exceptions allow
  # control of fibers. BaseException exceptions can encapsulate a value and thus
  # provide a way to interrupt long-running blocking operations while still
  # passing a value back to the call site. BaseException exceptions can also
  # references a cancel scope in order to allow correct bubbling of exceptions
  # through nested cancel scopes.
  class BaseException < ::Exception
    attr_reader :value

    def initialize(value = nil)
      @caller_backtrace = caller
      @value = value
    end

    def backtrace
      sanitize(@caller_backtrace)
    end
  end

  # MoveOn is used to interrupt a long-running blocking operation, while
  # continuing the rest of the computation.
  class MoveOn < BaseException; end

  # Cancel is used to interrupt a long-running blocking operation, bubbling the
  # exception up through cancel scopes and supervisors.
  class Cancel < BaseException; end

  # Terminate is used to interrupt a fiber once its parent fiber has terminated.
  class Terminate < BaseException; end

  # Restart is used to restart a fiber
  class Restart < BaseException; end

  # Interjection is used to run arbitrary code on arbitrary fibers at any point
  class Interjection < BaseException
    def initialize(proc)
      @proc = proc
    end

    def invoke
      @proc.call
    end
  end
end
