# frozen_string_literal: true

require_relative '../../polyphony'

module Polyphony
  # Implements a unidirectional communication channel along the lines of Go
  # (buffered) channels.
  class Channel < Polyphony::Queue
    alias_method :receive, :shift

    # Closes the channel, resuming any fibers waiting on the channel with
    # a Polyphony::MoveOn exception
    def close
      flush_waiters(Polyphony::MoveOn.new)
    end
  end
end
