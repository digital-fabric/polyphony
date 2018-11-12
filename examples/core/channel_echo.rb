# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def echo(rchan, wchan)
  while msg = (await rchan.receive)
    puts "got #{msg}"
    wchan << "you said: #{msg}"
  end
rescue Nuclear::Stopped
  puts "echoer stopped"
end

chan1, chan2 = Nuclear::Channel.new, Nuclear::Channel.new

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
