# frozen_string_literal: true

require_relative '../polyphony'

at_exit do
  repl = (Pry.current rescue nil) || (IRB.CurrentContext rescue nil)

  # in most cases, once the main fiber is done there are still pending
  # operations going on. If the reactor loop is not done, we suspend the root
  # fiber until it is done

  if $__reactor_fiber__&.alive? && !repl
    suspend
  end
end
