# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def timeout(t)
  Nuclear.promise do |p|
    Nuclear.timeout(t) { p.reject(RuntimeError.new("hello")) }
  end
end

Nuclear.async do
  t1 = Time.now
  
  result = Nuclear.await timeout(2), timeout(1), timeout(3)
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Nuclear.interval(1) { puts Time.now }
