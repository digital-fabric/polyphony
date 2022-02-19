# frozen_string_literal: true

require_relative '../core/global_api'

# Object extensions (methods available to all objects / call sites)
class ::Object
  include Polyphony::GlobalAPI
end
