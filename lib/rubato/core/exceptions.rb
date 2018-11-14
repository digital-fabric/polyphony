# frozen_string_literal: true

export :CoroutineInterrupt, :MoveOn, :Stop, :Cancel

class CoroutineInterrupt < ::Exception
  attr_reader :scope, :value

  def initialize(scope = nil, value = nil)
    @scope = scope
    @value = value
  end
end

class Stop < CoroutineInterrupt; end
class MoveOn < CoroutineInterrupt; end
class Cancel < CoroutineInterrupt; end
