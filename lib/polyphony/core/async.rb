# frozen_string_literal: true

export :async_decorate, :call_proc_with_optional_block

Coroutine = import('./coroutine')
FiberPool = import('./fiber_pool')

# Converts a regular method into an async method, i.e. a method that returns a
# proc that eventually executes the original code.
# @param receiver [Object] object receiving the method call
# @param sym [Symbol] method name
# @return [void]
def async_decorate(receiver, sym)
  sync_sym = :"sync_#{sym}"
  receiver.alias_method(sync_sym, sym)
  receiver.define_method(sym) do |*args, &block|
    Coroutine.new { send(sync_sym, *args, &block) }
  end
end

# Calls a proc with a block if both are given. Otherwise, call the first
# non-nil proc. This allows syntax such as:
#
#     # in fact, the call to #nexus returns a proc which takes a block
#     await nexus { ... }
#
# @param proc [Proc] proc A
# @param block [Proc] proc B
# @return [any] return value of proc invocation
def call_proc_with_optional_block(proc, block)
  if proc && block
    proc.call(&block)
  else
    (proc || block).call
  end
end
