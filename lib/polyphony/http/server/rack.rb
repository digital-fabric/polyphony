# frozen_string_literal: true

export :load

require 'rack'

def run(app)
  ->(req) { respond(req, app.(env(req))) }
end

def load(path)
  src = IO.read(path)
  instance_eval(src, path, 1)
end

# Implements a rack input stream:
# https://www.rubydoc.info/github/rack/rack/master/file/SPEC#label-The+Input+Stream
class InputStream
  def initialize(request)
    @request = request
  end

  def gets; end

  def read(length = nil, outbuf = nil); end

  def each(&block)
    @request.each_chunk(&block)
  end

  def rewind; end
end

def env(request)
  {
    'REQUEST_METHOD'                 => request.method,
    'SCRIPT_NAME'                    => '',
    'PATH_INFO'                      => request.path,
    'QUERY_STRING'                   => request.query_string || '',
    'SERVER_NAME'                    => request.headers['Host'], # ?
    'SERVER_PORT'                    => '80', # ?
    'rack.version'                   => Rack::VERSION,
    'rack.url_scheme'                => 'https', # ?
    'rack.input'                     => InputStream.new(request),
    'rack.errors'                    => STDERR, # ?
    'rack.multithread'               => false,
    'rack.run_once'                  => false,
    'rack.hijack?'                   => false,
    'rack.hijack'                    => nil,
    'rack.hijack_io'                 => nil,
    'rack.session'                   => nil,
    'rack.logger'                    => nil,
    'rack.multipart.buffer_size'     => nil,
    'rack.multipar.tempfile_factory' => nil
  }.tap do |env|
    request.headers.each { |k, v| env["HTTP_#{k.upcase}"] = v }
  end
end

def respond(request, (status_code, headers, body))
  headers[':status'] = status_code.to_s
  puts "headers: #{headers.inspect}"
  request.respond(body.first, headers)
end
