# frozen_string_literal: true

require 'polyphony'

if Object.constants.include?(:Reline)
  puts "reline"
  class Reline::ANSI
    def self.select(read_ios = [], write_ios = [], error_ios = [], timeout = nil)
      # p [:select, read_ios, timeout]
      # puts caller.join("\n")
      raise if read_ios.size > 1
      raise if write_ios.size > 0
      raise if error_ios.size > 0

      # p 1
      fiber = Fiber.current
      timer = spin do
        sleep timeout
        fiber.cancel
      end
      # p 2
      read_ios.each do |io|
        # p wait: io
        Polyphony.backend_wait_io(io, false)
        # p :done_wait
        return [io]
      end
      # p 3
    rescue Polyphony::Cancel
      # p :cancel
      return nil
    ensure
      # p :ensure
      timer.stop
      # p :ensure_done      
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
