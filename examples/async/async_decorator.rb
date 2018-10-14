# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

module Kernel
  def async(sym)
    sync_sym = :"sync_#{sym}"
    singleton_class.alias_method(sync_sym, sym)
    singleton_class.define_method(sym) do |*args, &block|
      Nuclear.async { send(sync_sym, *args, &block) }
    end
  end
end

async def sleep_a_bit
  puts "sleeping a bit..."
  Nuclear.await Nuclear.sleep(1)
  puts "done!"
end

# no async wrapper!
sleep_a_bit
