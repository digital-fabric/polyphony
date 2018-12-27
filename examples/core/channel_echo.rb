# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def echo(rchan, wchan)
  puts "start echoer"
  while msg = rchan.receive
    wchan << "you said: #{msg}"
  end
ensure
  puts "echoer stopped"
end

chan1, chan2 = Rubato::Channel.new, Rubato::Channel.new

echoer = spawn { echo(chan1, chan2) }

spawn do
  puts "start receiver"
  while msg = chan2.receive
    puts msg
  end
ensure
  puts "receiver stopped"
end

spawn do
  puts "send hello"
  chan1 << "hello"
  puts "send world"
  chan1 << "world"

  sleep 0.1
  
  puts "closing channels"
  chan1.close
  chan2.close
end
