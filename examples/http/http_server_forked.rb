# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

::Exception.__disable_sanitized_backtrace__ = true

opts = {
  reuse_addr:  true,
  dont_linger: true
}

server = Polyphony::HTTP::Server.listen('0.0.0.0', 1234, opts)

puts 'Listening on port 1234'

child_pids = []
4.times do
  pid = Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each do |req|
      req.respond("Hello world! from pid: #{Process.pid}\n")
    end
  rescue Interrupt
  end
  child_pids << pid
end

child_pids.each { |pid| Gyro::Child.new(pid).await }
