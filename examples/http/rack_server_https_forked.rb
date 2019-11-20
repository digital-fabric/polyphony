# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'localhost/authority'

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
app = Polyphony::HTTP::Rack.load(app_path)

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}
server = Polyphony::HTTP::Server.listen('0.0.0.0', 1234, opts)
puts 'Listening on port 1234'

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each(&app)
  end
end

child_pids.each { |pid| EV::Child.new(pid).await }
