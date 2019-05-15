# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

enum = [1,2,3].each

spawn do
  while e = enum.next rescue nil
    puts e
    sleep 1
  end
end
