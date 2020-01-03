# Refactor core.rb

- Put core class patches in core_ext.rb
- Put API in api.rb

# Add ability to cancel multiple coprocesses

```ruby
scope = CancelScope.new

3.times { |i|
  spin {
    puts "sleep for #{i + 1}s"
    scope.call { sleep i + 1 }
    puts "woke up"
  }
}

sleep 0.5
scope.cancel!
```

# Add ability to wait for signal

```ruby
sig = Gyro::Signal('SIGUP')

loop do
  sig.await
  restart
end
```

# Better API for multiple coprocess supervision

```ruby
# wait for all, raise exception raised in any coprocess
Coprocess.join(coproc1, coproc2, ...)
#=> returns array of results from coprocesses

# wait for first that finishes from multiple coprocs
Coprocess.select(coproc1, coproc2)
```

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

## 0.23 More API work and tests

- Tests for all APIs
- Awaiting on recurring timer (with compensation for timer drift)

  ```ruby
  timer = Gyro::Timer.new(1, 1)
  loop do
    timer.await
    puts Time.now.to_f
  end
  ```

- Cancel multiple coprocesses with single cancel scope:

  ```ruby
  scope = CancelScope.new

  3.times do
    spin do
      scope.call do
        do_some_work
      end
    end
  end

  sleep 0.5
  scope.cancel!
  ```

## 0.24 Full Rack adapter implementation

- Work better mechanism supervising multiple coprocesses (`when_done` feels a
  bit hacky)
- Add supervisor test
- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?
- find some demo Rack apps and test with Polyphony

## 0.25 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.26 Support for multi-threading

- Separate event loop for each thread

## 0.27 Testing

- test thread / thread_pool modules
- report test coverage

## 0.28 Documentation

## 0.29 Integration

- Sidekick
- Rails?

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

