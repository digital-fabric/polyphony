# Extending Polyphony

Polyphony was designed to ease the transition from blocking APIs and 
callback-based API to non-blocking, fiber-based ones. It is important to
understand that not all blocking calls can be easily converted into 
non-blocking calls. That might be the case with Ruby gems based on C-extensions,
such as database libraries. In that case, Polyphony's built-in
[thread pool](#threadpool) might be used for offloading such blocking calls.

### Adapting callback-based APIs

Some of the most common patterns in Ruby APIs is the callback pattern, in which
the API takes a block as a callback to be called upon completion of a task. One
such example can be found in the excellent
[http_parser.rb](https://github.com/tmm1/http_parser.rb/) gem, which is used by
Polyphony itself to provide HTTP 1 functionality. The `HTTP:Parser` provides 
multiple hooks, or callbacks, for being notified when an HTTP request is
complete. The typical callback-based setup is as follows:

```ruby
require 'http/parser'
@parser = Http::Parser.new

def on_receive(data)
  @parser < data
end

@parser.on_message_complete do |env|
  process_request(env)
end
```

A program using `http_parser.rb` in conjunction with Polyphony might do the
following:

```ruby
require 'http/parser'
require 'polyphony'

def handle_client(client)
  parser = Http::Parser.new
  req = nil
  parser.on_message_complete { |env| req = env }
  loop do
    parser << client.read
    if req
      handle_request(req)
      req = nil
    end
  end
end
```

Another possibility would be to monkey-patch `Http::Parser` in order to
encapsulate the state of the request:

```ruby
class Http::Parser
  def setup
    self.on_message_complete = proc { @request_complete = true }
  end

  def parser(data)
    self << data
    return nil unless @request_complete

    @request_complete = nil
    self
  end
end

def handle_client(client)
  parser = Http::Parser.new
  loop do
    if req == parser.parse(client.read)
      handle_request(req)
    end
  end
end
```
