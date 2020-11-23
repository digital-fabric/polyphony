# frozen_string_literal: true

require_relative '../../polyphony'
require 'pg'

# PG overrides
module ::PG
  def self.connect(*args)
    Connection.connect_start(*args).tap(&method(:connect_async))
  end

  def self.connect_async(conn)
    socket_io = conn.socket_io
    while true
      res = conn.connect_poll
      case res
      when PGRES_POLLING_FAILED   then raise Error, conn.error_message
      when PGRES_POLLING_READING  then Thread.current.backend.wait_io(socket_io, false)
      when PGRES_POLLING_WRITING  then Thread.current.backend.wait_io(socket_io, true)
      when PGRES_POLLING_OK       then return conn.setnonblocking(true)
      end
    end
  end

  def self.connect_sync(conn)
    while true
      res = conn.connect_poll
      case res
      when PGRES_POLLING_FAILED
        raise Error, conn.error_message
      when PGRES_POLLING_OK
        conn.setnonblocking(true)
        return
      end
    end
  end
end

# Overrides for PG connection
class ::PG::Connection
  alias_method :orig_get_result, :get_result

  def get_result(&block)
    while is_busy
      Thread.current.backend.wait_io(socket_io, false)
      consume_input
    end
    orig_get_result(&block)
  end

  alias_method :orig_async_exec, :async_exec
  def async_exec(*args, &block)
    send_query(*args)
    get_result(&block)
  ensure
    # cleanup result in order to allow next query
    while get_result; end
  end

  def block(_timeout = 0)
    while is_busy
      Thread.current.backend.wait_io(socket_io, false)
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
  def transaction(&block)
    return yield if @transaction # allow nesting of calls to #transactions

    perform_transaction(&block)
  end

  def perform_transaction
    query(SQL_BEGIN)
    began = true
    @transaction = true
    yield
    query(SQL_COMMIT)
  rescue StandardError => e
    query(SQL_ROLLBACK) if began
    raise e
  ensure
    @transaction = false
  end

  self.async_api = true

  def wait_for_notify(timeout = nil, &block)
    return move_on_after(timeout) { wait_for_notify(&block) } if timeout

    while true
      Thread.current.backend.wait_io(socket_io, false)
      consume_input
      notice = notifies
      next unless notice

      values = notice.values
      block&.(*values)
      return values.first
    end
  end
end
