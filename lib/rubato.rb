# frozen_string_literal: true

require 'modulation/gem'

export_default :Rubato

rubato = import('./rubato/core')
Exceptions = import('./rubato/core/exceptions')

module Rubato
  Cancel        = Exceptions::Cancel
  Channel       = import('./rubato/core/channel')
  Coroutine     = import('./rubato/core/coroutine')
  FiberPool     = import('./rubato/core/fiber_pool')
  FS            = import('./rubato/fs')
  IO            = import('./rubato/io')
  LineReader    = import('./rubato/line_reader')
  MoveOn        = Exceptions::MoveOn
  # Net           = import('./rubato/net')
  ResourcePool  = import('./rubato/resource_pool')
  Stream        = import('./rubato/stream')
  Supervisor    = import('./rubato/core/supervisor')
  Sync          = import('./rubato/core/sync')
  Thread        = import('./rubato/core/thread')
  ThreadPool    = import('./rubato/core/thread_pool')
end
