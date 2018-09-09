# frozen_string_literal: true

export_default :Core

module Core
  extend import('./core/async')
  extend import('./core/reactor')
end