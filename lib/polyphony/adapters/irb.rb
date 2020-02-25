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
        fiber.cancel!
      end
      read_ios.each do |io|
        io.read_watcher.await
        return [io]
      end
    rescue Polyphony::Cancel
      return nil
    ensure
      timer.stop
    end
  end
end
  
  # readline blocks the current thread, so we offload it to the blocking-ops
  # thread pool. That way, the reactor loop can keep running while waiting for
  # readline to return
  module ::Readline
    alias_method :orig_readline, :readline

    def readline(*args)
      p :readline
      async = Gyro::Async.new
      Thread.new do
        result = orig_readline(*args)
        async.signal!(result)
      end
      async.await
    end
  end
# end