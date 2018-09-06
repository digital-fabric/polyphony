# frozen_string_literal: true

require 'pg'

export :Connection

Core  = import('../core')
IO    = import('../io')

# Asynchronous PostgreSQL connection
class Connection < IO
  # Initializes connection
  def initialize(opts)
    @conn = ::PG.connect(opts)
    @conn.setnonblocking(true)
    @conn.type_map_for_results = ::PG::BasicTypeMapForResults.new(@conn)

    super(::IO.new(@conn.socket), connected: true)

    @queue = []
    @busy = false
  end

  # Issues a query, returning a promise. The promise is queued if another query
  # is already in progress
  # @return [Promise]
  def query(*args)
    Core::Async.promise do |p|
      if @busy
        @queue << [args, p]
      else
        send_query(args, p)
        @busy = true
      end
    end
  end

  # Sends query to backend
  # @param args [Array] array of query arguments
  # @param promise [Promise] associated promise
  # @return [void]
  def send_query(args, promise)
    @result_promise = promise
    @conn.send_query(*args)
  end

  # Consumes input from connection, resolving query result if applicable
  # @return [void]
  def read_from_io
    @conn.consume_input
    return if @conn.is_busy

    @result_promise.resolve(@conn.get_result)
    @conn.get_result # needed to allow next query
    if @queue.empty?
      @busy = false
    else
      send_query(*@queue.shift)
    end
  end
end
