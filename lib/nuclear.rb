# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

Nuclear = import('./nuclear/core')

module Nuclear
  FiberPool     = import('./nuclear/core/fiber_pool')
  FS            = import('./nuclear/fs')
  IO            = import('./nuclear/io')
  LineReader    = import('./nuclear/line_reader')
  Net           = import('./nuclear/net')
  Promise       = import('./nuclear/core/promise')
  ResourcePool  = import('./nuclear/resource_pool')
  Stream        = import('./nuclear/stream')
  Task          = import('./nuclear/core/task')
  Thread        = import('./nuclear/thread')
  ThreadPool    = import('./nuclear/thread_pool')
end
