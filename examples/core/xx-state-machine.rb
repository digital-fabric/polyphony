# frozen_string_literal: true

# require 'bundler/setup'
# require 'polyphony'

require 'fiber'

class StateMachine < ::Fiber
  def initialize(state, rules)
    @state = state
    @rules = rules
    super() { |input| state_loop(input) }
  end

  attr_reader :state
  def state_loop(input)
    loop do
      @state = apply(input)
      input = Fiber.yield(@state)
    end
  end

  def apply(input)
    f = @rules[@state][input]
    return f.(@state) if f.is_a?(Proc)

    raise 'Invalid input'
  rescue => e
    @state
  end

  def transition(input)
    state = self.resume(input)
    # state.is_a?(Exception) ? (raise state) : state
  end
end

o = StateMachine.new(
  :off,
  {
    off: { turnon: ->(s) { :on } },
    on: { turnoff: ->(s) { :off } }
  }
)

loop do
  STDOUT << "#{o.state}: "
  input = gets.strip.to_sym
  # puts "  command: #{input.inspect}"
  o.transition(input)
end
