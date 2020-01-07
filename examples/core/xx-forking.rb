# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "parent pid: #{Process.pid}"

pid = Polyphony.fork do
  puts "child pid: #{Process.pid}"

  spin do
    puts 'child going to sleep 1...'
    sleep 1
    puts 'child woke up 1'
  end

  suspend
end

puts "got child pid #{pid}"

puts 'parent waiting for child'
Gyro::Child.new(pid).await
puts 'parent done waiting'
