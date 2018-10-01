# frozen_string_literal: true

require_relative './ev_ext'

module EV
  def self.timeout(t, &cb)
    Timer.new(t, 0, &cb)
  end

  def self.interval(t, &cb)
    Timer.new(t, t, &cb)
  end
end
