# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

module ::Kernel
  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.first.is_a?(String)
      if args.size > 1
        format("%s: %p\n", args.shift, args)
      else
        format("%s\n", args.first)
      end
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end

  def monotonic_clock
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end

count = 10

f = spin do
  count.times { spin { suspend } }
  suspend
end

snooze
trace children_alive: f.children.size

trace 'shutting down children...'
f.shutdown_all_children

trace children_alive: f.children.size
