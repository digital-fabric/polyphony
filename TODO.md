# Roadmap:

## 0.22 Full Rack adapter implementation

- Work better mechanism supervising multiple coprocesses (`when_done` feels a
  bit hacky)
- Add supervisor test
- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?
- find some demo Rack apps and test with Polyphony

## 0.23 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.24 Support for multi-threading

- Separate event loop for each thread

## 0.25 Testing

- test thread / thread_pool modules
- report test coverage

## 0.26 Documentation

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

