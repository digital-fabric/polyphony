# frozen_string_literal: true

require_relative 'helper'

class SocketTest < MiniTest::Test
  def setup
    super
  end

  def test_tcp
    server = TCPServer.new('127.0.0.1', 1234)

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
    client = TCPSocket.new('127.0.0.1', 1234)
    client.write("1234\n")
    assert_equal "1234\n", client.readpartial(8192)
    client.close
  ensure
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end
end
