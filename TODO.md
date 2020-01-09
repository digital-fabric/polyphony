## 0.25 Merge Coprocess functionality into Fiber

- Merge `Coprocess` functionality into `Fiber`
  - Get rid of the duality Coprocess - Fiber
  - exception handling
  - interrupting (`MoveOn`/`Cancel`)
  - message passing (`receive`/`send`)
  - Clear separation between scheduling code and event handling code
  - Check performance difference using `http_server.rb`. We should expect a
    modest increase in throughput, as well as significantly less memory usage.
- Handle calls to `#sleep` without duration (should just `#suspend`)

## 0.26 Move Other interface code into separate gem

- Pull out redis/postgres code, put into new `polyphony-contrib` gem

## 0.27 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.28 Support for multi-threading

- Separate event loop for each thread

## 0.29 Testing && Docs

## 0.30 Integration

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

