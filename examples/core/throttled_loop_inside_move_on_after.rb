# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

i = 0
value = move_on_after(1, with_value: 42) do
  throttled_loop(20) do
    p (i += 1)
  end
end

p value: value
