# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

resp = Polyphony::HTTP::Agent.get('https://realiteq.net/?q=time')
puts "*" * 40
puts resp.body

__END__

X = 1
Y = 1
t0 = Time.now
supervise { |s|
  X.times {
    s.spin {
      Y.times {
        resp = Polyphony::HTTP::Agent.get('http://about.gitlab.com/')
        puts "*" * 40
        p resp.headers
        puts "*" * 40
        puts resp.body
        # puts "body size: #{resp.body.bytesize}"
      }
    }
  }
}
elapsed = Time.now - t0
puts "\nelapsed: #{elapsed} rate: #{(X * Y) / elapsed}"