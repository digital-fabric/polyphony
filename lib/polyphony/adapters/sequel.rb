# frozen_string_literal: true

require_relative '../../polyphony'
require 'sequel'

module Polyphony

  # Sequel ConnectionPool that delegates to Polyphony::ResourcePool.
  class FiberConnectionPool < Sequel::ConnectionPool

    # Initializes the connection pool.
    #
    # @param db [any] db to connect to
    # @paral opts [Hash] connection pool options
    def initialize(db, opts = OPTS)
      super
      max_size = Integer(opts[:max_connections] || 4)
      @pool = Polyphony::ResourcePool.new(limit: max_size) { make_new(:default) }
    end

    # Holds a connection from the pool, passing it to the given block.
    #
    # @return [any] block's return value
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

    # Returns the pool's size.
    #
    # @return [Integer] size of pool
    def size
      @pool.size
    end

    # Returns the pool's maximal size.
    #
    # @return [Integer] maximum pool size
    def max_size
      @pool.limit
    end

    # Fills pool and preconnects all db instances in pool.
    #
    # @return [void]
    def preconnect(_concurrent = false)
      @pool.fill!
    end
  end

  # Override Sequel::Database to use FiberConnectionPool by default.
  Sequel::Database.prepend(Module.new do
    def connection_pool_default_options
      { pool_class: FiberConnectionPool }
    end
  end)
end
