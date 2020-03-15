# frozen_string_literal: true

require 'bundler/setup'

class E < Exception
  def initialize(msg)
    super
    # set_backtrace(caller)
  end

  alias_method :orig_backtrace, :backtrace
  def backtrace
    b = orig_backtrace
    p [:backtrace, b, caller]
    b
  end
end

def e1
  e2
end

def e2
  E.new('foo')
end

def e3
  raise E, 'bar'
end

e = e1
p e
puts e.backtrace&.join("\n")

begin
  e3
rescue Exception => e
  p e
  puts e.backtrace.join("\n")
end