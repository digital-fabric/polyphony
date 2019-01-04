# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')
Rack = import('../../lib/polyphony/http/rack')

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
rack = Rack.load(app_path)

authority = Localhost::Authority.fetch
opts = {
  reuse_addr: true,
  dont_linger: true,
  secure_context: authority.server_context
}
runner = HTTPServer.listen('0.0.0.0', 1234, opts, &rack)
puts "Listening on port 1234"

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    spawn(&runner)
  end
end

spawn do
  child_pids.each { |pid| EV::Child.new(pid).await }
end