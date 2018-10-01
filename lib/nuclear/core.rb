# frozen_string_literal: true

export_default :Core

# Core module, containing async and reactor methods
module Core
  extend import('./core/async')
end
