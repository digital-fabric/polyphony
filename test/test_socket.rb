# frozen_string_literal: true

require_relative 'helper'
require 'fileutils'

class SocketTest < MiniTest::Test
  def setup
    super
  end

  def test_tcp
    port = rand(1234..5678)
    server = TCPServer.new('127.0.0.1', port)

    server_fiber = spin do
      while (socket = server.accept)
        spin do
          while (data = socket.gets(8192))
            socket << data
          end
        end
      end
    end

    snooze
    client = TCPSocket.new('127.0.0.1', port)
    client.write("1234\n")
    assert_equal "1234\n", client.recv(8192)
    client.close
  ensure
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end

  def test_unix_socket
    path = '/tmp/test_unix_socket'
    FileUtils.rm(path) rescue nil
    server = UNIXServer.new(path)
    server_fiber = spin do
      server.accept_loop do |socket|
        spin do
          while (data = socket.gets(8192))
            socket << data
          end
        end
      end
    end

    snooze
    client = UNIXSocket.new(path)
    client.write("1234\n")
    assert_equal "1234\n", client.recv(8192)
    client.close
  ensure
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end
end

class HTTPClientTest < MiniTest::Test
  require 'json'

  def test_http
    res = HTTParty.get('http://worldtimeapi.org/api/timezone/Europe/Paris')
    response = JSON.load(res.body)
    assert_equal "CET", response['abbreviation']
  end

  def test_https
    res = HTTParty.get('https://worldtimeapi.org/api/timezone/Europe/Paris')
    response = JSON.load(res.body)
    assert_equal "CET", response['abbreviation']
  end
end