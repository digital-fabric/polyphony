# frozen_string_literal: true

export_default :Core

module Core
  Async       = import('./core/async')
  IO          = import('./core/io')
  LineReader  = import('./core/line_reader')
  Net         = import('./core/net')
  Promise     = import('./core/promise')
  Reactor     = import('./core/reactor')
  Stream      = import('./core/stream')
  Thread      = import('./core/thread')
end
