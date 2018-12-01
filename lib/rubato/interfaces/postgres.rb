# frozen_string_literal: true

export :Client

require 'pg'

Core  = import('../core')
IO    = import('../io')

module ::PG
  def self.connect(*args)
    puts "connect"
    connect_method = Fiber.current.root? ? :connect_sync : :connect_async
    Connection.connect_start(*args).tap(&method(connect_method))
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
    result = get_result(&block)
    while get_result; end
    result
  end

  def block(timeout = 0)
    while is_busy
      socket_io.read_watcher.await
      consume_input
    end
  end

  self.async_api = true
end
