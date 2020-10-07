# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
::Exception.__disable_sanitized_backtrace__ = true

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
end

i, o = IO.pipe

buf = []
f = spin do
  buf << :ready
  # loop do
  #   s = Thread.current.backend.read(i, +'', 6, false)
  #   trace read_result: s
  #   break if s.nil?
  #   buf << s
  # rescue Exception => e
  #   trace exception: e
  #   raise e
  # end
  Thread.current.backend.read_loop(i) { |d| buf << d }
  buf << :done
end

# writing always causes snoozing
o << 'foo'
o << 'bar'
trace '...closing'
o.close
trace '...closed'

f.await

raise "Bad result: #{buf.inspect}" unless buf == [:ready, 'foo', 'bar', :done]

puts '-' * 80
p buf