# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'localhost/authority'

# p Polyphony::HTTP::Agent.get('https://ui.realiteq.net/', q: :time)

BASE_URL = 'http://realiteq.net'

CACHE = {}.freeze

def proxy(uri, opts)
  now = Time.now
  uri = BASE_URL + uri
  entry = CACHE[uri]
  return entry[:response] if entry && entry[:expires] >= now

  puts "proxy => #{uri} (#{opts.inspect})"
  response = Polyphony::HTTP::Agent.get(uri, opts)
  # CACHE[uri] = {
  #   expires: now + 60,
  #   response: response
  # }
  response
end

HEADERS_BLACK_LIST = %w[
  Transfer-Encoding Date Server Connection Content-Length Cache-Control
  :method :authority :scheme :path
].freeze

def sanitize_headers(headers)
  headers.reject { |k, _v| HEADERS_BLACK_LIST.include?(k) }
end

def sanitize_html(html)
  # html.gsub('http://martigny-le-comte.fr/', '/')
end

# authority = Localhost::Authority.fetch

rsa_cert = OpenSSL::X509::Certificate.new(
  IO.read('../reality/aws/config/ssl/full_chain.pem')
)
rsa_pkey = OpenSSL::PKey.read(
  IO.read('../reality/aws/config/ssl/private_key.pem')
)
ctx = OpenSSL::SSL::SSLContext.new
ctx.add_certificate(rsa_cert, rsa_pkey)

opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: ctx # authority.server_context
}

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    puts "#{req.method} #{req.uri}"
    puts "headers <: #{req.headers.inspect}"
    # h = {
    #   uri: req.uri.to_s,
    #   protocol: req.protocol,
    #   headers: req.headers,
    #   body: req.body,
    # }
    response = proxy(req.uri.to_s, headers: sanitize_headers(req.headers))
    headers = sanitize_headers(response[:headers])
    body = response[:body]
    # puts "body class: #{body.class}"
    puts "headers >: #{response[:headers].inspect}"
    # body = sanitize_html(body) if headers['Content-Type'] =~ /text\/html/
    req.respond(body, headers)
  rescue StandardError => e
    puts 'error'
    p e
    puts e.backtrace.join("\n")
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
