# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

Nuclear = import('./nuclear/core')

module Nuclear
  VERSION = '0.7'

  FS            = import('./nuclear/fs')
  IO            = import('./nuclear/io')
  LineReader    = import('./nuclear/line_reader')
  Net           = import('./nuclear/net')
  Promise       = import('./nuclear/core/promise')
  ResourcePool  = import('./nuclear/resource_pool')
  Stream        = import('./nuclear/stream')
  Thread        = import('./nuclear/thread')
  ThreadPool    = import('./nuclear/thread_pool')
end
