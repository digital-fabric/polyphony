# Roadmap:

## 0.16 - Reogranize code:

- different functionalities are loaded using `require`:

  ```ruby
  require 'polyphony'
  require 'polyphony/http'
  # The HTTP server module actually requires the core module, so the first
  # require is superfluous.
  require 'polyphony/postgres'
  ...
  ```
- modules are organized as follows:

  ```ruby
  Polyphony::Core # loads extensions for `Kernel`, `IO`, `Socket`, `SSL`
  Polyphony::HTTP
    Polyphony::HTTP::Server
    Polyphony::HTTP::Agent
  Polyphony::Redis
  ...
  ```

- Clean up code while moving it around

## 0.17 Full or almost full functionality of `IO` using monkey patching

- testing - check conformance to Ruby `IO` API (as described in the Ruby docs)
- implement as much as possible in C

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

- benchmarks!

## 0.21 Testing

- test thread / thread_pool modules
- report test coverage

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
