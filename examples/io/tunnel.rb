# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

if ARGV.size < 2
  puts "Usage: ruby examples/tunnel.rb <port1> <port2>"
  exit
end

Ports = ARGV[0..1]
EndPoints = []

def log(msg)
  puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')} #{msg}"
end

def endpoint_loop(idx, peer_idx)
  port = Ports[idx]
  server = Polyphony::Net.tcp_listen(
    '0.0.0.0',
    port,
    reuse_addr: true
  ) 
  # server = TCPServer.open('0.0.0.0', port)
  log "Listening on port #{port}"
  loop do
    conn = server.accept
    conn.binmode
    EndPoints[idx] = conn
    log "Client connected on port #{port} (#{conn.remote_address.inspect})"
    conn.read_loop do |data|
      peer = EndPoints[peer_idx]
      if peer
        peer << data
        log "#{idx} => #{peer_idx} #{data.inspect}"
      else
        log "#{idx}: #{data.inspect}"
      end
    end
    EndPoints[idx] = nil
    log "Connection closed on port #{port}"
  rescue => e
    log "Error on port #{port}: #{e.inspect}"
  end
end

spin { endpoint_loop(0, 1) }
spin { endpoint_loop(1, 0) }

log "Tunneling port #{Ports[0]} to port #{Ports[1]}..."
sleep

