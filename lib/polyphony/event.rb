# frozen_string_literal: true

module Polyphony
  # Event watcher for thread-safe synchronisation
  class Event
    def initialize
      @i, @o = IO.pipe
    end

    def await
      Thread.current.agent.read(@i, +'', 1, false)
      raise @value if @value.is_a?(Exception)

      @value
    end

    def await_no_raise
      Thread.current.agent.read(@i, +'', 1, false)
      @value
    end

    def signal(value = nil)
      @value = value
      Thread.current.agent.write(@o, '1')
    end
  end
end
