# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'fileutils'

unix_path = '/tmp/polyphony-unix-socket'

FileUtils.rm unix_path rescue nil
server = UNIXServer.new(unix_path)
spin do
  server.accept_loop do |socket|
    p [:accept, socket]
    spin do
      while (line = socket.gets)
        socket.puts line
      end
    end
  end
end

snooze
client = UNIXSocket.new('/tmp/polyphony-unix-socket')
p [:connected, client]
client.puts 'hello!'
p client.gets
