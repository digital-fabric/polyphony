# Roadmap:

## 0.18 Working net/http, httparty

- implement `TCPSocket`/`TCPServer` functionality
- test `socket` classes
- test `Net::HTTP`
- test `httparty`

## 0.19 Full Rack adapter implementation

- follow Rack specification (doesn't have to include stuff like streaming or
  websockets)
- find some demo Rack apps and test with Polyphony

## 0.20 Working Rails application

- app with database access (postgresql)
- benchmarks!

## 0.21 Support for multi-threading

- Separate event loop for each thread

## 0.22 Testing

- test thread / thread_pool modules
- report test coverage

## 0.23 Documentation

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
