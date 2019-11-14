# frozen_string_literal: true

require 'fiber'

class Fiber
  class << self
    alias_method :orig_new, :new
    def new(&block)
      calling_fiber = Fiber.current
      fiber_caller = caller
      fiber_caller.concat calling_fiber.caller if calling_fiber&.caller
      orig_new do |value|
        fiber = Fiber.current
        fiber.calling_fiber = calling_fiber
        fiber.caller = fiber_caller
        block.(value)
      rescue Exception => e
        e.set_backtrace(e.backtrace + fiber_caller)
        raise e
      end
    end
  end

  attr_accessor :calling_fiber, :caller

  def combine_backtrace(backtrace)
    backtrace = backtrace + @caller if @caller
    @calling_fiber ?
      @calling_fiber.combine_backtrace(backtrace) : backtrace
  end
end

f = Fiber.new do
  g = Fiber.new do
    puts "f.caller: #{f.caller.inspect}"
    puts "g.caller: #{g.caller.inspect}"

    raise 'hi'
  end
  g.resume
end

f.resume

puts 'done'