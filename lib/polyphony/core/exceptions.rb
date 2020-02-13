# frozen_string_literal: true

export :Interrupt, :MoveOn, :Cancel, :Terminate

# Common exception class for interrupting fibers. These exceptions allow
# control of fibers. Interrupt exceptions can encapsulate a value and thus
# provide a way to interrupt long-running blocking operations while still
# passing a value back to the call site. Interrupt exceptions can also
# references a cancel scope in order to allow correct bubbling of exceptions
# through nested cancel scopes.
class Interrupt < ::Exception
  attr_reader :scope, :value

  def initialize(scope = nil, value = nil)
    @scope = scope
    @value = value
  end
end

# MoveOn is used to interrupt a long-running blocking operation, while
# continuing the rest of the computation.
class MoveOn < Interrupt; end

# Cancel is used to interrupt a long-running blocking operation, bubbling the
# exception up through cancel scopes and supervisors.
class Cancel < Interrupt; end

# Terminate is used to interrupt a fiber once its parent fiber has terminated.
class Terminate < Interrupt; end
