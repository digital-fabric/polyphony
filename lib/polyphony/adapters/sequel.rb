# frozen_string_literal: true

require_relative '../../polyphony'
require 'sequel'

module Polyphony
  # Sequel ConnectionPool that delegates to Polyphony::ResourcePool.
  class FiberConnectionPool < Sequel::ConnectionPool
    def initialize(db, opts = OPTS)
      super
      max_size = Integer(opts[:max_connections] || 4)
      @pool = Polyphony::ResourcePool.new(limit: max_size) { make_new(:default) }
    end

    def hold(_server = nil)
      @pool.acquire do |conn|
        yield conn
      rescue Polyphony::BaseException
        # The connection may be in an unrecoverable state if interrupted,
        # discard the connection from the pool so it isn't reused.
        @pool.discard!
        raise
      end
    end

    def size
      @pool.size
    end

    def max_size
      @pool.limit
    end

    def preconnect(_concurrent = false)
      @pool.preheat!
    end
  end

  # Override Sequel::Database to use FiberConnectionPool by default.
  Sequel::Database.prepend(Module.new do
    def connection_pool_default_options
      { pool_class: FiberConnectionPool }
    end
  end)
end
