# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

supervisor = spin do
  puts "parent pid #{Process.pid}"

  Polyphony::ProcessSupervisor.supervise do
    puts "child pid #{Process.pid}"
    puts "go to sleep"
    sleep 5
  rescue Interrupt
    puts "child got INT"
  rescue SystemExit
    puts "child got TERM"
  ensure
    puts "done sleeping"
  end
end

begin
  supervisor.await
rescue Interrupt
  exit!
  # supervisor.terminate
  # supervisor.await
end