# frozen_string_literal: true

require 'modulation/gem'

export_default :Nuclear

Nuclear = import('./nuclear/core')
Exceptions = import('./nuclear/core/exceptions')

module Nuclear
  Cancelled     = Exceptions::Cancelled
  Channel       = import('./nuclear/core/channel')
  FiberPool     = import('./nuclear/core/fiber_pool')
  FS            = import('./nuclear/fs')
  # IO            = import('./nuclear/io')
  IO            = import('./nuclear/io_wrapper')
  LineReader    = import('./nuclear/line_reader')
  Net           = import('./nuclear/net')
  ResourcePool  = import('./nuclear/resource_pool')
  Stopped       = Exceptions::Stopped
  Stream        = import('./nuclear/stream')
  Supervisor    = import('./nuclear/core/supervisor')
  Sync          = import('./nuclear/core/sync')
  Task          = import('./nuclear/core/task')
  Thread        = import('./nuclear/core/thread')
  ThreadPool    = import('./nuclear/core/thread_pool')
end
