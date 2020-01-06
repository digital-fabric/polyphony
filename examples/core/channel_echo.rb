# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def echo(cin, cout)
  puts 'start echoer'
  while (msg = cin.receive)
    cout << "you said: #{msg}"
  end
ensure
  puts 'echoer stopped'
end

chan1, chan2 = 2.times.map { Polyphony::Channel.new }

spin { echo(chan1, chan2) }

spin do
  puts 'start receiver'
  while (msg = chan2.receive)
    puts msg
    $main.resume if msg =~ /world/
  end
ensure
  puts 'receiver stopped'
end

$main = spin do
  puts 'start main'
  t0 = Time.now
  puts 'send hello'
  chan1 << 'hello'
  puts 'send world'
  chan1 << 'world'

  suspend

  puts 'closing channels'
  chan1.close
  chan2.close
  puts "done #{Time.now - t0}"
end

suspend