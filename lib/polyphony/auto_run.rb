# frozen_string_literal: true

require_relative '../polyphony'

at_exit do
  unless Gyro.break?
    repl = (Pry.current rescue nil) || (IRB.CurrentContext rescue nil)

    # in most cases, once the root fiber is done there are still pending
    # operations going on. If the reactor loop is not done, we suspend the root
    # fiber until it is done
    begin
      suspend if !repl
    rescue Exception => e
      p e
      puts e.backtrace.join("\n")
    end
  end
end
