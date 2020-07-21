# frozen_string_literal: true

module Polyphony
  # Event watcher for thread-safe synchronisation
  class Event
    def await
      @fiber = Fiber.current
      Thread.current.agent.wait_event(true)
    end

    def signal(value = nil)
      @fiber&.schedule(value)
    ensure
      @fiber = nil
    end
  end
end
