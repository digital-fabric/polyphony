# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

input = Polyphony::IO.lines(Polyphony::IO.stdin)

Polyphony.async do
  Polyphony.interval(1) { puts Time.now }

  loop do
    Polyphony::IO.stdout << "Say something: "
    l = Polyphony.await(input)
    break unless l
    Polyphony::IO.stdout << "You said: #{l}"
  end
end
