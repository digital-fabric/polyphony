# frozen_string_literal: true

require_relative 'helper'
require 'fileutils'
require 'msgpack'

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

  def test_read
    port = rand(1234..5678)
    server = TCPServer.new('127.0.0.1', port)
    server_fiber = spin do
      while (socket = server.accept)
        spin do
          while (data = socket.read(8192))
            socket << data
          end
        end
      end
    end

    snooze
    client = TCPSocket.new('127.0.0.1', port)

    client << 'hi'
    assert_equal 'hi', client.read(2)

    client << 'foobarbaz'
    assert_equal 'foo', client.read(3)
    assert_equal 'bar', client.read(3)

    buf = +'abc'
    assert_equal 'baz', client.read(3, buf)
    assert_equal 'baz', buf

    buf = +'def'
    client << 'foobar'
    assert_equal 'deffoobar', client.read(6, buf, -1)
    assert_equal 'deffoobar', buf

    client.close
  ensure
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end

  # sending multiple strings at once
  def test_sendv
    port = rand(1234..5678)
    server = TCPServer.new('127.0.0.1', port)

    server_fiber = spin do
      while (socket = server.accept)
        spin do
          while (data = socket.gets(8192))
            socket.write("you said ", data)
          end
        end
      end
    end

    snooze
    client = TCPSocket.new('127.0.0.1', port)
    client.write("1234\n")
    assert_equal "you said 1234\n", client.recv(8192)
    client.close
  ensure
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end


  def test_feed_loop
    port = rand(1234..5678)
    server = TCPServer.new('127.0.0.1', port)

    server_fiber = spin do
      reader = MessagePack::Unpacker.new
      while (socket = server.accept)
        spin do
          socket.feed_loop(reader, :feed_each) do |msg|
            msg = { 'result' => msg['x'] + msg['y'] }
            socket << msg.to_msgpack
          end
        end
      end
    end

    snooze
    client = TCPSocket.new('127.0.0.1', port)
    reader = MessagePack::Unpacker.new
    client << { 'x' => 13, 'y' => 14 }.to_msgpack
    result = nil
    client.feed_loop(reader, :feed_each) do |msg|
      result = msg
      break
    end
    assert_equal({ 'result' => 27}, result)
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
  skip unless IS_LINUX

  require 'json'

  def test_http
    res = HTTParty.get('http://ipinfo.io/')

    response = JSON.load(res.body)
    assert_equal 'https://ipinfo.io/missingauth', response['readme']
  end

  def test_https
    res = HTTParty.get('https://ipinfo.io/')
    response = JSON.load(res.body)
    assert_equal 'https://ipinfo.io/missingauth', response['readme']
  end
end