# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')

opts = {
  reuse_addr: true,
  dont_linger: true,
}
runner = HTTPServer.listener('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end

puts "Listening on port 1234"

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    spawn(&runner)
  end
end

child_pids.each { |pid| EV::Child.new(pid).await }
