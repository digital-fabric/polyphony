# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

Nuclear = import('./nuclear/core')

module Nuclear
  FiberPool     = import('./nuclear/core/fiber_pool')
  FS            = import('./nuclear/fs')
  # IO            = import('./nuclear/io')
  IO            = import('./nuclear/io_wrapper')
  LineReader    = import('./nuclear/line_reader')
  Net           = import('./nuclear/net')
  ResourcePool  = import('./nuclear/resource_pool')
  Stream        = import('./nuclear/stream')
  Sync          = import('./nuclear/core/sync')
  Thread        = import('./nuclear/core/thread')
  ThreadPool    = import('./nuclear/core/thread_pool')
end
