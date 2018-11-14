# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

input = Rubato::IO.lines(Rubato::IO.stdin)

Rubato.async do
  Rubato.interval(1) { puts Time.now }

  loop do
    Rubato::IO.stdout << "Say something: "
    l = Rubato.await(input)
    break unless l
    Rubato::IO.stdout << "You said: #{l}"
  end
end
