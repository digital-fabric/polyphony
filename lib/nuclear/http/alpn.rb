# frozen_string_literal: true

export :setup, :alpn_protocol

ALPN_PROTOCOLS = %w[h2 http/1.1].freeze

# Sets up ALPN protocols negotiated during handshake
# @return [void]
def setup(context)
  context.alpn_protocols = ALPN_PROTOCOLS
  context.alpn_select_cb = proc do |protocols|
    # select first common protocol
    (ALPN_PROTOCOLS & protocols).first
  end
end

H2_PROTOCOL = 'h2'

# returns the ALPN protocol used for the given socket
# @param socket [Net::Socket] socket
# @return [String, nil]
def alpn_protocol(socket)
  socket.secure? && socket.raw_io.alpn_protocol
end
