# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def timeout(t)
  Nuclear.promise { |p| Nuclear.timeout(t, &p) }
end

Nuclear.async do
  t1 = Time.now
  
  result = Nuclear.await *[2, 1.5, 3].map(&method(:timeout))
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Nuclear.interval(1) { puts Time.now }
