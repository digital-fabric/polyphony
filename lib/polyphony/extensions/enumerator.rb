# frozen_string_literal: true

# Extensions to the Enumerator class
class ::Enumerator
  alias_method :orig_next, :next
  def next
    Fiber.current.thread ||= Thread.current
    orig_next
  end

  alias_method :orig_each, :each
  def each(*a, &b)
    Fiber.current.thread ||= Thread.current
    orig_each(*a, &b)
  end
end
