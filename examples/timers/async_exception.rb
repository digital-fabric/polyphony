# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def test
  Nuclear.timeout(1) { raise 'hi!' }
end

class Exception
  ASYNC_BOUNDARY = ['-' * 40]

  def async_backtrace
    return backtrace + ASYNC_BOUNDARY + source_backtrace
  end

  def source_backtrace
    bt = Kernel.instance_variable_get(:@callback_source_backtrace)
    bt&.reject { |f| f =~ /lib\/nuclear/ }
  end
end

begin
  test
  EV.run
rescue => e
  puts "got error: #{e.message}"
  puts e.async_backtrace.join("\n")
end