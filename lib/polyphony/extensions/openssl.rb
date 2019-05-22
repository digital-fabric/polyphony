# frozen_string_literal: true

require 'openssl'

import('./socket')

class ::OpenSSL::SSL::SSLSocket
  def dont_linger
    io.dont_linger
  end

  def no_delay
    io.no_delay
  end

  def reuse_addr
    io.reuse_addr
  end
end