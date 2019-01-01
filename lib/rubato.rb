# frozen_string_literal: true

require 'modulation/gem'

export_default :Rubato

Rubato = import('./rubato/core')
Exceptions = import('./rubato/core/exceptions')

module Rubato
  Cancel        = Exceptions::Cancel
  MoveOn        = Exceptions::MoveOn

  auto_import(
    Channel:      './rubato/core/channel',
    Coroutine:    './rubato/core/coroutine',
    Sync:         './rubato/core/sync',
    Thread:       './rubato/core/thread',
    ThreadPool:   './rubato/core/thread_pool',
  
    FS:           './rubato/fs',
    Net:          './rubato/net',
    ResourcePool: './rubato/resource_pool',
    Supervisor:   './rubato/supervisor'
  )
end
