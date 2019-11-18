# frozen_string_literal: true

require_relative 'helper'
require 'polyphony/http'

import '../lib/polyphony/http/server/http1.rb'

class IO
  # Creates two mockup sockets for simulating server-client communication
  def self.server_client_mockup
    server_in, client_out = IO.pipe
    client_in, server_out = IO.pipe

    server_connection = mockup_connection(server_in, server_out, client_out)
    client_connection = mockup_connection(client_in, client_out, server_out)

    [server_connection, client_connection]
  end

  def self.mockup_connection(i, o, oo)
    eg(
      :read         => ->(*args) { i.read(*args) },
      :readpartial  => ->(*args) { i.readpartial(*args) },
      :<<           => ->(*args) { o.write(*args) },
      :write        => ->(*args) { o.write(*args) },
      :close        => -> { o.close },
      :eof?         => -> { oo.closed? }
    )
  end
end

class HTTP1ServerTest < MiniTest::Test
  def teardown
    @server&.interrupt if @server.alive?
    snooze
    super
  end

  def spin_server(&handler)
    server_connection, client_connection = IO.server_client_mockup
    coproc = spin do
      Polyphony::HTTP::Server.client_loop(server_connection, {}, &handler)
    rescue Exception => e
      # p e
      # puts e.backtrace.join("\n")
    end
    [coproc, client_connection, server_connection]
  end

  def test_that_server_uses_content_length_in_http_1_0
    @server, connection = spin_server do |req|
      req.respond("Hello, world!", {})
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.0\r\n\r\n"

    response = connection.readpartial(8192)
    assert_equal("HTTP/1.0 200\r\nContent-Length: 13\r\n\r\nHello, world!", response)
  end

  def test_that_server_uses_chunked_encoding_in_http_1_1
    @server, connection = spin_server do |req|
      req.respond("Hello, world!", {})
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.1\r\n\r\n"

    response = connection.readpartial(8192)
    assert_equal("HTTP/1.1 200\r\nTransfer-Encoding: chunked\r\n\r\nd\r\nHello, world!\r\n0\r\n\r\n", response)
  end

  def test_that_server_maintains_connection_when_using_keep_alives
    @server, connection = spin_server do |req|
      req.respond('Hi', {})
    end

    connection << "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n"
    response = connection.readpartial(8192)
    assert !connection.eof?
    assert_equal("HTTP/1.0 200\r\nContent-Length: 2\r\n\r\nHi", response)

    connection << "GET / HTTP/1.1\r\n\r\n"
    response = connection.readpartial(8192)
    assert !connection.eof?
    assert_equal("HTTP/1.1 200\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nHi\r\n0\r\n\r\n", response)

    connection << "GET / HTTP/1.0\r\n\r\n"
    response = connection.readpartial(8192)
    assert connection.eof?
    assert_equal("HTTP/1.0 200\r\nContent-Length: 2\r\n\r\nHi", response)
  end
end