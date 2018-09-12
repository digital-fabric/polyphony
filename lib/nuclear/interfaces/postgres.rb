# frozen_string_literal: true

export :Client

require 'pg'

Core  = import('../core')
IO    = import('../io')

# Connection establishment methods
module Connection
  def connect
    close if @raw_io
    @connection = PG::Connection.connect_start(@opts)
    @io = @connection.socket_io
    
    Core.promise do |p|
      @connect_promise = p
      connect_async
    end
  end

  def connect_async
    case @connection.connect_poll
    when PG::PGRES_POLLING_FAILED
      remove_monitor
      @io = nil
      @connect_promise.error PG::Error.new(@connection.error_message)
    when PG::PGRES_POLLING_READING
      update_monitor_interests(:r)
    when PG::PGRES_POLLING_WRITING
      update_monitor_interests(:w)
    when PG::PGRES_POLLING_OK
      @connected = true
      finalize_connection
    end
  end

  def finalize_connection
    @connection.setnonblocking(true)
    set_type_map
    @connect_promise.resolve(true)
  end

  def handle_selected(monitor)
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

  def transaction(&block)
    unless Fiber.current.async?
      raise RuntimeError, 'transaction can only be called inside async block'
    end

    began = false
    return block.() if @transaction # allow nesting of calls to #transactions
    
    Core.await query(SQL_BEGIN)
    @transaction = true
    began = true
    block.()
    Core.await query(SQL_COMMIT)
  rescue => e
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
      puts "sql: #{args.first}"
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

  def fulfill_query_promise(result)
    result.check
    @query_promise.resolve(result)
  rescue => e
    @query_promise.error(e)
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

    # if @connected
    # @conn = ::PG.connect(opts)
    # @connection.setnonblocking(true)
    # @connection.type_map_for_results = ::PG::BasicTypeMapForResults.new(@conn)

    # super(::IO.new(@connection.socket), connected: true)

    @queue = []
    @busy = false
  end

  # Set type map for connection
  def set_type_map
    @connection.type_map_for_results =
      ::PG::BasicTypeMapForResults.new(@connection)
  end
end
