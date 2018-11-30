# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  async {
    puts "going to sleep..."
    sleep 1
    puts "woke up"
  }.await
end
