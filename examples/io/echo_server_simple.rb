# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn {
  server = TCPServer.open(1234)
  while client = server.accept
    spawn {
      while data = client.read rescue nil
        client.write(data)
      end
    }
  end
}
