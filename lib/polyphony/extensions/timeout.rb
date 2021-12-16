# frozen_string_literal: true

require 'timeout'

# Override Timeout to use cancel scope
module ::Timeout
  def self.timeout(sec, klass = Timeout::Error, message = 'execution expired', &block)
    cancel_after(sec, with_exception: [klass, message], &block)
  end
end
