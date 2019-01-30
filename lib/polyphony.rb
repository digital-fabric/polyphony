# frozen_string_literal: true

require 'modulation/gem'

export_default :Polyphony

Polyphony = import('./polyphony/core')
Exceptions = import('./polyphony/core/exceptions')

import('polyphony/extensions/socket')
import('polyphony/extensions/ssl')

module Polyphony
  Cancel        = Exceptions::Cancel
  MoveOn        = Exceptions::MoveOn

  Net = import('./polyphony/net')

  auto_import(
    Channel:      './polyphony/core/channel',
    Coprocess:    './polyphony/core/coprocess',
    Sync:         './polyphony/core/sync',
    Thread:       './polyphony/core/thread',
    ThreadPool:   './polyphony/core/thread_pool',
  
    FS:           './polyphony/fs',
    # Net:          './polyphony/net',
    ResourcePool: './polyphony/resource_pool',
    Supervisor:   './polyphony/supervisor'
  )
end
