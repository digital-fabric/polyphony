# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'polyphony/auto_run'

Exception.__disable_sanitized_backtrace__ = true

X = 1
Y = 1
t0 = Time.now
supervise { |s|
  X.times {
    s.spin {
      Y.times {
        resp = Polyphony::HTTP::Agent.get('http://gitlab.com/')
        puts "body size: #{resp.body.bytesize}"
      }
    }
  }
}
elapsed = Time.now - t0
puts "\nelapsed: #{elapsed} rate: #{(X * Y) / elapsed}"