# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

Nuclear = import('./nuclear/core')

module Nuclear
  VERSION = '0.3'

  Promise     = import('./nuclear/core/promise')

  IO          = import('./nuclear/io')
  LineReader  = import('./nuclear/line_reader')
  Net         = import('./nuclear/net')
  Stream      = import('./nuclear/stream')
  Thread      = import('./nuclear/thread')
end
