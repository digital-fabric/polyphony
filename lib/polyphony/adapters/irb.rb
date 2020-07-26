# frozen_string_literal: true

require 'polyphony'

if Object.constants.include?(:Reline)
  class Reline::ANSI
    def self.select(read_ios = [], write_ios = [], error_ios = [], timeout = nil)
      p [:select, read_ios]
      raise if read_ios.size > 1
      raise if write_ios.size > 0
      raise if error_ios.size > 0

      fiber = Fiber.current
      timer = spin do
        sleep timeout
        fiber.cancel
      end
      read_ios.each do |io|
        Thread.current.agent.wait_io(io, false)
        return [io]
      end
    rescue Polyphony::Cancel
      return nil
    ensure
      timer.stop
    end
  end
else
  require_relative './readline'

  # RubyLex patches
  class ::RubyLex
    class TerminateLineInput2 < RuntimeError
    end
    const_set(:TerminateLineInput, TerminateLineInput2)
  end
end
