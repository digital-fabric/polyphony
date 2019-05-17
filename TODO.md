## Testing

- test IO
- test TCP server / client
- test thread / thread_pool modules

## UDP socket

```ruby
socket = UDPSocket.new
socket.bind("127.0.0.1", 1234)

socket.send "message-to-self", 0, "127.0.0.1", 1234
p socket.recvfrom(10)
#=> ["message-to", ["AF_INET", 4913, "localhost", "127.0.0.1"]]
```

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
