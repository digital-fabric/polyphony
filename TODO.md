# HTTP Client Agent

The concurrency model and the fact that we want to serve the response object on
receiving headers and let the user lazily read the response body, means we'll
need to change the API to accept a block:

```ruby
# current API
resp = Agent.get('http://acme.org')
puts resp.body

# proposed API
Agent.get('http://acme.org') do |resp|
  puts resp.body
end
```

While the block is running, the connection adapter is acquired. Once the block
is done running, the request (and response) can be discarded. The problem with
that if we spin up a coprocess from that block we risk all kinds of race
conditions and weird behaviours.

A compromise might be to allow the two: doing a `get` without providing a block
will return a response object that already has the body (i.e. the entire
response has already been received). Doing a `get` with a block will invoke the
block once headers are received, letting the user's code stream the body:

```ruby
def request(ctx, &block)
  ...
  connection_manager.acquire do |adapter|
    response = adapter.request(ctx)
    if block
      block.(response)
    else
      # wait for body
      response.body
    end
    response
  end
end
```

# Roadmap:

## 0.22 Redesign of Gyro scheduling system

- Schedulerless design - no separate fiber for running ev loop
- Blocking operations directly transfer to first scheduled fiber
- Scheduled fibers managed using linked list, switching directly from one to the
  other

## 0.23 Full Rack adapter implementation

- Work better mechanism supervising multiple coprocesses (`when_done` feels a
  bit hacky)
- Add supervisor test
- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?
- find some demo Rack apps and test with Polyphony

## 0.24 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.25 Support for multi-threading

- Separate event loop for each thread

## 0.26 Testing

- test thread / thread_pool modules
- report test coverage

## 0.27 Documentation

# DNS

## DNS client

```ruby
ip_address = DNS.lookup('google.com', 'A')
```

Prior art:

- https://github.com/alexdalitz/dnsruby
- https://github.com/eventmachine/eventmachine/blob/master/lib/em/resolver.rb
- https://github.com/gmodarelli/em-resolv-replace/blob/master/lib/em-dns-resolver.rb
- https://github.com/socketry/async-dns

### DNS server

```ruby
Server = import('../../lib/polyphony/dns/server')

server = Server.new do |transaction|
  puts "got query from #{transaction.info[:client_ip_address]}"
  transaction.questions.each do |q|
    respond(transaction, q[:domain], q[:resource_class])
  end
end

server.listen(port: 5300)
puts "listening on port 5300"
```

Prior art:

- https://github.com/socketry/async-dns

