# frozen_string_literal: true

require 'modulation/gem'

export_default :Rubato

rubato = import('./rubato/core')
Exceptions = import('./rubato/core/exceptions')

module rubato
  Cancelled     = Exceptions::Cancelled
  Channel       = import('./rubato/core/channel')
  FiberPool     = import('./rubato/core/fiber_pool')
  FS            = import('./rubato/fs')
  # IO            = import('./rubato/io')
  IO            = import('./rubato/io_wrapper')
  LineReader    = import('./rubato/line_reader')
  Net           = import('./rubato/net')
  ResourcePool  = import('./rubato/resource_pool')
  Stopped       = Exceptions::Stopped
  Stream        = import('./rubato/stream')
  Supervisor    = import('./rubato/core/supervisor')
  Sync          = import('./rubato/core/sync')
  Task          = import('./rubato/core/task')
  Thread        = import('./rubato/core/thread')
  ThreadPool    = import('./rubato/core/thread_pool')
end
