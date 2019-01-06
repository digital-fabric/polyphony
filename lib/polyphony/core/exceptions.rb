# frozen_string_literal: true

export :CoprocessInterrupt, :MoveOn, :Stop, :Cancel, :debug, :debug=

class CoprocessInterrupt < ::Exception
  attr_reader :scope, :value

  def initialize(scope = nil, value = nil)
    @scope = scope
    @value = value
  end
end

class Stop < CoprocessInterrupt; end
class MoveOn < CoprocessInterrupt; end
class Cancel < CoprocessInterrupt; end

def debug
  @debug
end

def debug=(value)
  @debug = value
end