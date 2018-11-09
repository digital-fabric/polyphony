# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def echo(rchan, wchan)
  loop do
    msg = await rchan.receive
    puts "got #{msg}"
    wchan << "you said: #{msg}"
  end
rescue Stopped
  puts "got Stopped"
end

chan1, chan2 = Nuclear::Channel.new, Nuclear::Channel.new

echoer = spawn echo(chan1, chan2)
puts "spawn: #{echoer.inspect}"

spawn do
  nexus do |n|
    nexus << 

    chan1 << "hello"
    chan1 << "world"
    msg = await chan2.receive
    puts msg

  chan1.close
  chan2.close
end
