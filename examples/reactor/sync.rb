# frozen_string_literal: true

# A way to run async ops synchronously

require 'modulation'

Nuclear = import('../../lib/nuclear')
import('../../lib/nuclear/test')

Nuclear.async do 
  t0 = Time.now
  Nuclear.await Nuclear.sleep(1)
  puts "Elapsed: #{Time.now - t0}"
end

