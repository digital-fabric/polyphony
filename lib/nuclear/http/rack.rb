# frozen_string_literal: true

export :run, :load_app

Server = import('./server')

def run(app)
  Server.new { |req, resp| handle(req, resp, app) }
end

require 'fileutils'

def load_app(path)
  src = IO.read(path)
  instance_eval(src)
end

def handle(request, response, app)
  render_rack_response response, app.(rack_env(request))
end

def rack_env(request)
  {

  }
end

def render_rack_response(response, (status_code, headers, body))
  response.write_head(status_code, headers)
  body.each do |chunk|
    response.write(chunk)
  end
  response.finish
end