# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'

import('./extensions/kernel')

# Core module, containing async and reactor methods
module Core
  def self.trap(sig, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &callback)
  end

  def self.at_exit(&block)
    @exit_tasks ||= []
    @exit_tasks << block
  end

  def self.run_exit_procs
    return unless @exit_tasks

    @exit_tasks.each { |t| t.call rescue nil }
  end

  def self.trap_int_signal
    @sigint_watcher = trap(:int) do
      puts
      EV.break
    end
    EV.unref # the signal trap should not keep the loop running
  end

  def self.run
    trap_int_signal
    
    EV.run
    Core.run_exit_procs
  ensure
    @sigint_watcher&.stop
    @sigint_watcher = nil
  end

  def self.auto_run
    return if @auto_ran
    @auto_ran = true
  
    return if $!

    run
  end

  def self.dont_auto_run!
    @auto_ran = true
  end
end

at_exit do
  Core.auto_run
end
