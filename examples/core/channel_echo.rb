# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def echo(rchan, wchan)
  while msg = (await rchan.receive)
    puts "got #{msg}"
    wchan << "you said: #{msg}"
  end
rescue Rubato::Stopped
  puts "echoer stopped"
end

chan1, chan2 = Rubato::Channel.new, Rubato::Channel.new

echoer = spawn echo(chan1, chan2)

spawn do
  chan1 << "hello"
  chan1 << "world"
  
  2.times do
    msg = await chan2.receive
    puts msg
  end

  chan1.close
  chan2.close
end
