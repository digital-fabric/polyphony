# frozen_string_literal: true

require_relative '../polyphony'

at_exit do
  p 'at_exit 1'
  repl = (Pry.current rescue nil) || (IRB.CurrentContext rescue nil)

  p 'at_exit 2'
  # in most cases, once the main fiber is done there are still pending
  # operations going on. If the reactor loop is not done, we suspend the root
  # fiber until it is done
  suspend if $__reactor_fiber__&.alive? && !repl

  p 'at_exit 3'
end
