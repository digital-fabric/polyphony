# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')

spawn do
  opts = { reuse_addr: true, dont_linger: true }
  server = HTTPServer.listen(nil, 1234, opts) do |req, resp|
    status_code = 200
    data = "Hello world!\n"
    headers = "Content-Length: #{data.bytesize}\r\n"
    await resp.socket.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
    # response.write_head(200, H_DATE => server_time)
    # response.finish(HELLO_WORLD)
  end

  await server
end

puts "pid: #{Process.pid}"