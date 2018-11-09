# frozen_string_literal: true

export :TaskInterrupted, :Stopped, :Cancelled

class TaskInterrupted < ::Exception
  attr_reader :scope

  def initialize(scope = nil)
    @scope = scope
  end
end

class Stopped < TaskInterrupted
end

class Cancelled < TaskInterrupted
end
