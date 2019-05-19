# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

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
    Polyphony::HTTP::Server.accept_loop(server, opts) do |req|
      req.respond("Hello world!\n")
    end
  rescue Interrupt
  end
end

child_pids.each { |pid| EV::Child.new(pid).await }