# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

module Nuclear
  VERSION = '0.3'

  Async       = import('./nuclear/core/async')
  IO          = import('./nuclear/core/io')
  LineReader  = import('./nuclear/core/line_reader')
  Net         = import('./nuclear/core/net')
  Promise     = import('./nuclear/core/promise')
  Reactor     = import('./nuclear/core/reactor')
  Stream      = import('./nuclear/core/stream')
  Thread      = import('./nuclear/core/thread')
end
