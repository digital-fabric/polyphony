# frozen_string_literal: true

export_default :Protocol

require 'http/2'

Stream = import './http2_stream'

class Protocol
  def self.upgrade_each(socket, opts, headers, &block)
    adapter = new(socket, opts, headers)
    adapter.each(&block)
  end

  def initialize(conn, opts, upgrade_headers = nil)
    @conn = conn  
    @opts = opts

    @interface = ::HTTP2::Server.new
    @interface.on(:frame) { |bytes| @conn << bytes }
    defer { upgrade(upgrade_headers) } if upgrade_headers
  end

  # request API
  
  UPGRADE_MESSAGE = <<~HTTP.gsub("\n", "\r\n")
  HTTP/1.1 101 Switching Protocols
  Connection: Upgrade
  Upgrade: h2c

  HTTP

def upgrade(headers)
    settings = headers['HTTP2-Settings']
    @conn << UPGRADE_MESSAGE
    @interface.upgrade(settings, headers, '')
  end

  # Iterates over incoming requests
  def each(&block)
    @interface.on(:stream) { |stream| Stream.new(stream, &block) }

    while (data = @conn.readpartial(8192)) do
      @interface << data
      snooze
    end
  rescue SystemCallError, IOError
    # ignore
  ensure
    # release references to various objects
    @interface = nil
    @conn.close
  end

  def close
    @conn.close
  end
end