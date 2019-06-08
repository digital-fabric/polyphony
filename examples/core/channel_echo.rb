# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def echo(rchan, wchan)
  puts "start echoer"
  while msg = rchan.receive
    wchan << "you said: #{msg}"
  end
ensure
  puts "echoer stopped"
end

chan1, chan2 = Polyphony::Channel.new, Polyphony::Channel.new

echoer = spin { echo(chan1, chan2) }

spin do
  puts "start receiver"
  while msg = chan2.receive
    puts msg
    $main.resume if msg =~ /world/
  end
ensure
  puts "receiver stopped"
end

$main = spin do
  t0 = Time.now
  puts "send hello"
  chan1 << "hello"
  puts "send world"
  chan1 << "world"

  suspend
  
  puts "closing channels"
  chan1.close
  chan2.close
  puts "done #{Time.now - t0}"
end
