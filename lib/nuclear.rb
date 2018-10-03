# frozen_string_literal: true

require 'modulation/gem'
require_relative './ev'

export_default :Nuclear

Nuclear = import('./nuclear/core')

module Nuclear
  VERSION = '0.7'

  FS            = import('./nuclear/fs')
  IO            = import('./nuclear/io')
  LineReader    = import('./nuclear/line_reader')
  Net           = import('./nuclear/net')
  Promise       = import('./nuclear/core/promise')
  ResourcePool  = import('./nuclear/resource_pool')
  Stream        = import('./nuclear/stream')
  Thread        = import('./nuclear/thread')
  ThreadPool    = import('./nuclear/thread_pool')

  def self.timeout(t, &cb)
    EV::Timer.new(t, 0, &cb)
  end

  def self.interval(t, &cb)
    EV::Timer.new(t, t, &cb)
  end

  def self.next_tick(&cb)
    EV::Timer.new(0, 0, &cb)
  end

  def self.trap(sig, &cb)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &cb)
  end
end

def auto_run
  Nuclear.trap(:int) { puts; EV.break }
  EV.run
rescue Exception => e
  puts "Exception: #{e}"
  puts e.backtrace.join("\n")
end

at_exit { auto_run }