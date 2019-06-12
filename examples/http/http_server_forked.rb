# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

opts = {
  reuse_addr: true,
  dont_linger: true,
}

server = Polyphony::HTTP::Server.listen('0.0.0.0', 1234, opts)

puts "Listening on port 1234"

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each do |req|
      req.respond("Hello world! from pid: #{Process.pid}\n")
    end
  rescue Interrupt
  end
end

child_pids.each { |pid| EV::Child.new(pid).await }