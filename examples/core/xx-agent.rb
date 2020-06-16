# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

class Test
  def test_sleep
    puts "going to sleep"
    sleep 1
    puts "done sleeping"
  end
  
  def test_spin
    spin {
      10.times {
        STDOUT << '.'
        sleep 0.1
      }
    }
    
    puts "going to sleep\n"
    sleep 1
    puts 'woke up'
  end
  
  def test_file
    f = File.open(__FILE__, 'r')
    puts Thread.current.agent.read(f, +'', 10000, true)
    
    Thread.current.agent.write(STDOUT, "Write something: ")
    str = +''
    Thread.current.agent.read(STDIN, str, 5, false)
    puts str
  end
  
  def test_fork
    pid = fork do
      Thread.current.agent.post_fork
      puts 'child going to sleep'
      sleep 1
      puts 'child done sleeping'
      exit(42)
    end
    
    puts "Waiting for pid #{pid}"
    result = Thread.current.agent.waitpid(pid)
    puts "Done waiting"
    p result
  end
  
  def test_async
    async = Polyphony::Event.new
    
    spin {
      puts "signaller starting"
      sleep 1
      puts "signal"
      async.signal(:foo)
    }
    
    puts "awaiting event"
    p async.await
  end
  
  def test_queue
    q = Gyro::Queue.new
    spin {
      10.times {
        q << Time.now.to_f
        sleep 0.2
      }
      q << :STOP
    }
    
    loop do
      value = q.shift
      break if value == :STOP
      
      p value
    end
  end
  
  def test_thread
    t = Thread.new do
      puts "thread going to sleep"
      sleep 0.2
      puts "thread done sleeping"
    end
    
    t.await
  end
end

t = Test.new

t.methods.select { |m| m =~ /^test_/ }.each do |m|
  puts '*' * 40
  puts m
  t.send(m)
end