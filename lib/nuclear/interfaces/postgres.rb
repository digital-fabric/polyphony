# frozen_string_literal: true

export :Client

require 'pg'

Core  = import('../core')
IO    = import('../io')

# Connection establishment methods
module Connection
  # Initiates an asynchronous connection to a PG server, returning a promise
  # @return [Promise]
  def connect
    close if @raw_io
    @connection = PG::Connection.connect_start(@opts)
    @io = @connection.socket_io

    Core.promise do |p|
      @connect_promise = p
      connect_async
    end
  end

  # Continues connection to PG server
  # @return [void]
  def connect_async
    case @connection.connect_poll
    when PG::PGRES_POLLING_FAILED
      connect_error
    when PG::PGRES_POLLING_READING
      update_event_mask(:r)
    when PG::PGRES_POLLING_WRITING
      update_event_mask(:w)
    when PG::PGRES_POLLING_OK
      finalize_connection
    end
  end

  # Handles connection error
  # @return [void]
  def connect_error
    remove_monitor
    @io = nil
    @connect_promise.reject PG::Error.new(@connection.error_message)
  end

  # Finalizes connection to PG server
  # @return [void]
  def finalize_connection
    @connected = true
    @connection.setnonblocking(true)
    set_type_map
    @connect_promise.resolve(true)
  end

  def read_from_io(_monitor)
    if !@connected && @connection
      connect_async
    else
      super
    end
  end
end

# Querying methods
module Query
  # Issues a query, returning a promise. The promise is queued if another query
  # is already in progress
  # @return [Promise]
  def query(*args)
    Core.promise do |p|
      if @busy
        @queue << [args, p]
      else
        send_query(args, p)
        @busy = true
      end
    end
  end

  SQL_BEGIN = 'begin'
  SQL_COMMIT = 'commit'
  SQL_ROLLBACK = 'rollback'

  MSG_ASYNC_TRANSACTION = 'transaction can only be called inside async block'

  # Starts a transaction, runs given block, and commits transaction. If an
  # error is raised, the transaction is rolled back and the error is raised
  # again.
  # @return [void]
  def transaction
    raise MSG_ASYNC_TRANSACTION unless Fiber.current.async?

    began = false
    return yield if @transaction # allow nesting of calls to #transactions

    Core.await query(SQL_BEGIN)
    began = true
    @transaction = true
    yield
    Core.await query(SQL_COMMIT)
  rescue StandardError => e
    Core.await query(SQL_ROLLBACK) if began
    raise e
  ensure
    @transaction = false
  end

  # Sends query to backend
  # @param args [Array] array of query arguments
  # @param promise [Promise] associated promise
  # @return [void]
  def send_query(args, promise)
    if @connected
      @query_promise = promise
      @connection.send_query(*args)
    else
      connect.then { send_query(args, promise) }
    end
  end

  # Consumes input from connection, resolving query result if applicable
  # @return [void]
  def read_from_io
    @connection.consume_input
    return if @connection.is_busy

    while (result = @connection.get_result)
      fulfill_query_promise(result)
    end

    if @queue.empty?
      @busy = false
    else
      send_query(*@queue.shift)
    end
  end

  # Resolves pending query promise with query result, handling any error
  # @param result [PG::Result] query result
  # @return [void]
  def fulfill_query_promise(result)
    result.check
    @query_promise.resolve(result)
  rescue StandardError => e
    @query_promise.reject(e)
  ensure
    result.clear
  end
end

# Corehronous PostgreSQL connection
class Client < IO
  include Connection
  include Query

  # Initializes connection
  def initialize(opts)
    @opts = opts
    @queue = []
    @busy = false
  end

  # Set type map for connection
  def set_type_map
    @connection.type_map_for_results = ImprovedTypeMap.new(@connection)
  end
end

# Improved type map - to deal with DBs with lots of tables
class ImprovedTypeMap < ::PG::BasicTypeMapForResults
  SQL_WITH_RANGES = <<~SQL
    SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput, r.rngsubtype
    FROM pg_type t
    LEFT JOIN pg_namespace n on n.oid = t.typnamespace
    LEFT JOIN pg_range as r ON t.oid = r.rngtypid
    WHERE n.nspname = 'pg_catalog'
      AND t.typname !~ '^(_|pg_)'
  SQL

  SQL_WITHOUT_RANGES = <<~SQL
    SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput
    FROM pg_type as t
    LEFT JOIN pg_namespace n on n.oid = t.typnamespace
    WHERE n.nspname = 'pg_catalog'
      AND t.typname !~ '^(_|pg_)'
  SQL

  CODER_ARRAY = [
    [0, :encoder, PG::TextEncoder::Array],
    [0, :decoder, PG::TextDecoder::Array],
    [1, :encoder, nil],
    [1, :decoder, nil]
  ].freeze

  # Builds hash of coder maps
  # @param connection [PG::Connection]
  # @return [Array] array of coder maps
  def build_coder_maps(connection)
    sql = supports_ranges?(connection) ? SQL_WITH_RANGES : SQL_WITHOUT_RANGES
    result = connection.exec(sql)

    CODER_ARRAY.each_with_object([]) do |(format, direction, arraycoder), a|
      a[format] ||= {}
      a[format][direction] = coder_map(result, format, direction, arraycoder)
    end
  end

  # Returns coder map
  def coder_map(result, format, direction, arraycoder)
    CoderMap.new result, CODERS_BY_NAME[format][direction], format, arraycoder
  end
end
