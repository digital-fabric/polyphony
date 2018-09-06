# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

module Nuclear
  Version = '0.3'

  Async   = import('./nuclear/async')
  Promise = import('./nuclear/promise')
  Reactor = import('./nuclear/reactor')
  Thread  = import('./nuclear/thread')
end
