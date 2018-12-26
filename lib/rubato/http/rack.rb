# frozen_string_literal: true

export :load

def run(app)
  ->(req) {
    response = app.(env(req))
    respond(req, response)
  }
end

def load(path)
  src = IO.read(path)
  instance_eval(src)
end

def env(request)
  { }
end

S_STATUS = ':status'

def respond(request, (status_code, headers, body))
  headers[S_STATUS] = status_code.to_s
  body = body.first
  request.respond(body, headers)
end