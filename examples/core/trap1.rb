# frozen_string_literal: true

pid = Process.pid
fork do
  sleep 1
  Process.kill('SIGINT', pid)
  # sleep 10
  # Process.kill(-9, pid)
end

require 'bundler/setup'
require 'polyphony'

Thread.backend.trace_proc = proc { |*e| STDOUT.orig_write("#{e.inspect}\n") }
trap('SIGINT') { STDOUT.orig_write("* recv SIGINT\n") }
# trap('SIGCHLD') { STDOUT.orig_write("* recv SIGCHLD\n") }
STDOUT.orig_write("* pre gets\n")
# STDIN.wait_readable
s = gets
p s
STDOUT.orig_write("* post gets\n")
