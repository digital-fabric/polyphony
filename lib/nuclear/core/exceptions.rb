# frozen_string_literal: true

export :TaskInterrupted, :Stopped, :Cancelled

class TaskInterrupted < ::Exception
  attr_reader :scope, :value

  def initialize(scope = nil, value = nil)
    @scope = scope
    @value = value
  end
end

class Stopped < TaskInterrupted
end

class Cancelled < TaskInterrupted
end
