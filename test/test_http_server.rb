# frozen_string_literal: true

require_relative 'helper'
require 'polyphony/http'

class String
  def http_lines
    gsub "\n", "\r\n"
  end
end

class IO
  # Creates two mockup sockets for simulating server-client communication
  def self.server_client_mockup
    server_in, client_out = IO.pipe
    client_in, server_out = IO.pipe

    server_connection = mockup_connection(server_in, server_out, client_out)
    client_connection = mockup_connection(client_in, client_out, server_out)

    [server_connection, client_connection]
  end

  def self.mockup_connection(input, output, output2)
    eg(
      :read        => ->(*args) { input.read(*args) },
      :readpartial => ->(*args) { input.readpartial(*args) },
      :<<          => ->(*args) { output.write(*args) },
      :write       => ->(*args) { output.write(*args) },
      :close       => -> { output.close },
      :eof?        => -> { output2.closed? }
    )
  end
end

class HTTP1ServerTest < MiniTest::Test
  def teardown
    @server&.interrupt if @server&.alive?
    snooze
    super
  end

  def spin_server(opts = {}, &handler)
    server_connection, client_connection = IO.server_client_mockup
    coproc = spin do
      Polyphony::HTTP::Server.client_loop(server_connection, opts, &handler)
    end
    [coproc, client_connection, server_connection]
  end

  def test_that_server_uses_content_length_in_http_1_0
    @server, connection = spin_server do |req|
      req.respond('Hello, world!', {})
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.0\r\n\r\n"

    response = connection.readpartial(8192)
    expected = <<~HTTP.chomp.http_lines
      HTTP/1.0 200
      Content-Length: 13

      Hello, world!
    HTTP
    assert_equal(expected, response)
  end

  def test_that_server_uses_chunked_encoding_in_http_1_1
    @server, connection = spin_server do |req|
      req.respond('Hello, world!')
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.1\r\n\r\n"

    response = connection.readpartial(8192)
    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      d
      Hello, world!
      0

    HTTP
    assert_equal(expected, response)
  end

  def test_that_server_maintains_connection_when_using_keep_alives
    puts 'test_that_server_maintains_connection_when_using_keep_alives'
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
    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      2
      Hi
      0

    HTTP
    assert_equal(expected, response)

    connection << "GET / HTTP/1.0\r\n\r\n"
    response = connection.readpartial(8192)
    assert connection.eof?
    assert_equal("HTTP/1.0 200\r\nContent-Length: 2\r\n\r\nHi", response)
  end

  def test_pipelining_client
    @server, connection = spin_server do |req|
      if req.headers['Foo'] == 'bar'
        req.respond('Hello, foobar!', {})
      else
        req.respond('Hello, world!', {})
      end
    end

    connection << "GET / HTTP/1.1\r\n\r\nGET / HTTP/1.1\r\nFoo: bar\r\n\r\n"
    response = connection.readpartial(8192)

    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      d
      Hello, world!
      0

      HTTP/1.1 200
      Transfer-Encoding: chunked

      e
      Hello, foobar!
      0

    HTTP
    assert_equal(expected, response)
  end

  def test_body_chunks
    chunks = []
    request = nil
    @server, connection = spin_server do |req|
      request = req
      req.send_headers
      req.each_chunk do |c|
        chunks << c
        req << c.upcase
      end
      req.finish
    end

    connection << <<~HTTP.http_lines
      POST / HTTP/1.1
      Transfer-Encoding: chunked

      6
      foobar
    HTTP
    2.times { snooze }
    assert request
    assert_equal %w[foobar], chunks
    assert !request.complete?

    connection << "6\r\nbazbud\r\n"
    snooze
    assert_equal %w[foobar bazbud], chunks
    assert !request.complete?

    connection << "0\r\n\r\n"
    snooze
    assert_equal %w[foobar bazbud], chunks
    assert request.complete?

    2.times { snooze }

    response = connection.readpartial(8192)

    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      6
      FOOBAR
      6
      BAZBUD
      0

    HTTP
    assert_equal(expected, response)
  end

  def test_upgrade
    done = nil

    opts = {
      upgrade: {
        echo: lambda do |conn, _headers|
          conn << <<~HTTP.http_lines
            HTTP/1.1 101 Switching Protocols
            Upgrade: echo
            Connection: Upgrade

          HTTP

          while (data = conn.readpartial(8192))
            conn << data
            snooze
          end
          done = true
        end
      }
    }

    @server, connection = spin_server(opts) do |req|
      req.respond('Hi')
    end

    connection << "GET / HTTP/1.1\r\n\r\n"
    response = connection.readpartial(8192)
    assert !connection.eof?
    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      2
      Hi
      0

    HTTP
    assert_equal(expected, response)

    connection << <<~HTTP.http_lines
      GET / HTTP/1.1
      Upgrade: echo
      Connection: upgrade

    HTTP

    snooze
    response = connection.readpartial(8192)
    assert !connection.eof?
    expected = <<~HTTP.http_lines
      HTTP/1.1 101 Switching Protocols
      Upgrade: echo
      Connection: Upgrade

    HTTP
    assert_equal(expected, response)

    assert !done

    connection << 'foo'
    assert_equal 'foo', connection.readpartial(8192)

    connection << 'bar'
    assert_equal 'bar', connection.readpartial(8192)

    connection.close
    assert !done
    snooze
    assert done
  end

  def test_big_download
    chunk_size = 100_000
    chunk_count = 10
    chunk = '*' * chunk_size
    @server, connection = spin_server do |req|
      req.send_headers
      chunk_count.times do
        req << chunk
        snooze
      end
      req.finish
      req.adapter.close
    end

    response = +''
    count = 0

    connection << "GET / HTTP/1.1\r\n\r\n"
    while (data = connection.readpartial(chunk_size * 2))
      response << data
      count += 1
      snooze
    end

    chunks = "#{chunk_size.to_s(16)}\n#{'*' * chunk_size}\n" * chunk_count
    expected = <<~HTTP.http_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      #{chunks}0

    HTTP

    assert_equal expected, response
    assert_equal chunk_count * 2 + 1, count
  end
end
