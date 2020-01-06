# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'http/2'

# Response = import '../../lib/polyphony/http/client/response'

url = 'https://realiteq.net/?q=time'
uri = URI(url)
uri_key = { scheme: uri.scheme, host: uri.host, port: uri.port }

ctx = {
  method: :GET,
  uri:    uri,
  opts:   {},
  retry:  0
}

SECURE_OPTS = { secure: true, alpn_protocols: ['h2', 'http/1.1'] }.freeze
socket = Polyphony::Net.tcp_connect(uri_key[:host], uri_key[:port], SECURE_OPTS)

puts 'connected'

$client = HTTP2::Client.new
$client.on(:frame) { |bytes| socket << bytes }
$client.on(:frame_received) do |frame|
  puts "Received frame: #{frame.inspect}"
end
# $client.on(:frame_sent) do |frame|
#   puts "Sent frame: #{frame.inspect}"
# end

reader = spin do
  while (data = socket.readpartial(8192))
    $client << data
    snooze
  end
end

stream = $client.new_stream

$headers = nil
$done = nil
@buffered_chunks = []

@waiting_headers_fiber = nil
@waiting_chunk_fiber = nil
@waiting_done_fiber = nil

# send request
headers = {
  ':method'    => ctx[:method].to_s,
  ':scheme'    => ctx[:uri].scheme,
  ':authority' => [ctx[:uri].host, ctx[:uri].port].join(':'),
  ':path'      => ctx[:uri].request_uri,
  'User-Agent' => 'curl/7.54.0'
}
headers.merge!(ctx[:opts][:headers]) if ctx[:opts][:headers]

if ctx[:opts][:payload]
  stream.headers(headers, end_stream: false)
  stream.data(ctx[:opts][:payload], end_stream: true)
else
  stream.headers(headers, end_stream: true)
end

stream.on(:headers) { |headers|
  puts "got headers"
  # if @waiting_headers_fiber
  #   @waiting_headers_fiber.transfer headers.to_h
  # else
    $headers = headers.to_h
  # end
}
stream.on(:data) { |chunk|
  puts "got data"
  # if @waiting_chunk_fiber
  #   @waiting_chunk_fiber&.transfer c
  # else
    @buffered_chunks << chunk
  # end
}

def close
  puts "got close"
  $done = true
end

stream.on(:close) { close }
  # @waiting_done_fiber&.transfer
# }

stream.on(:active) { puts "* active" }
stream.on(:half_close) { puts "* half_close" }



# wait for response
# unless $headers
#   @waiting_headers_fiber = Fiber.current
#   $headers = suspend
# end
# p $headers
# response = Response.new(self, $headers[':status'].to_i, $headers)
# p response

puts "waiting for response"
while !$done
  puts "waiting..."
  sleep 1
end
puts "done"

#   def body
#     @waiting_chunk_fiber = Fiber.current
#     body = +''
#     while !$done
#       chunk = suspend
#       body << chunk
#     end
#     body
#   rescue => e
#     p e
#     puts e.backtrace.join("\n")
#   end
# end

# adapter = StreamAdapter.new
# resp = adapter.request(ctx)
# puts "*" * 40
# p resp

# body = resp.body
# p body