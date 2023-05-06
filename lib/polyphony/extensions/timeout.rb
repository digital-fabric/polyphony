# frozen_string_literal: true

require 'timeout'

# Timeout extensions
module ::Timeout

  # Sets a timeout for the given block. This method provides an equivalent API
  # to the stock Timeout API provided by Ruby. In case of a timeout, the block
  # will be interrupted and an exception will be raised according to the given
  # arguments.
  #
  # @param sec [Number] timeout period in seconds
  # @param klass [Class] exception class
  # @param message [String] exception message
  # @yield [] code to run
  # @return [any] block's return value
  def self.timeout(sec, klass = Timeout::Error, message = 'execution expired', &block)
    cancel_after(sec, with_exception: [klass, message], &block)
  end
end
