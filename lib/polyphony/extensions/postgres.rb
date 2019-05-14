# frozen_string_literal: true

export :Client

require 'pg'

Core  = import('../core')

module ::PG
  def self.connect(*args)
    Connection.connect_start(*args).tap(&method(:connect_async))
  end
  
  def self.connect_async(conn)
    loop do
      res = conn.connect_poll
      case res
      when PGRES_POLLING_FAILED   then raise Error.new(conn.error_message)
      when PGRES_POLLING_READING  then conn.socket_io.read_watcher.await
      when PGRES_POLLING_WRITING  then conn.socket_io.write_watcher.await
      when PGRES_POLLING_OK       then
        conn.setnonblocking(true)
        return
      end
    end
  ensure
    conn.socket_io.stop_watchers
  end

  def self.connect_sync(conn)
    loop do
      res = conn.connect_poll
      case res
      when PGRES_POLLING_FAILED   then raise Error.new(conn.error_message)
      when PGRES_POLLING_OK       then
        conn.setnonblocking(true)
        return
      end
    end
  end
end

class ::PG::Connection
  alias_method :orig_get_result, :get_result
  
  def get_result(&block)
    while is_busy
      socket_io.read_watcher.await
      consume_input
    end
    orig_get_result(&block)
  ensure
    socket_io.stop_watchers
  end

  alias_method :orig_async_exec, :async_exec
  def async_exec(*args, &block)
    send_query(*args)
    get_result(&block)
  ensure
    # cleanup result in order to allow next query
    while get_result; end
  end

  def block(timeout = 0)
    while is_busy
      socket_io.read_watcher.await
      consume_input
    end
  end

  SQL_BEGIN = 'begin'
  SQL_COMMIT = 'commit'
  SQL_ROLLBACK = 'rollback'

  # Starts a transaction, runs given block, and commits transaction. If an
  # error is raised, the transaction is rolled back and the error is raised
  # again.
  # @return [void]
  def transaction
    began = false
    return yield if @transaction # allow nesting of calls to #transactions

    query(SQL_BEGIN)
    began = true
    @transaction = true
    yield
    query(SQL_COMMIT)
  rescue StandardError => e
    (query(SQL_ROLLBACK) rescue nil) if began
    raise e
  ensure
    @transaction = false if began
  end

  self.async_api = true
end
