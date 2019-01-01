## Testing

- test EV layer: `EV.run`, watchers: IO, timer, signal (and `Core.trap`), async
- test promises / async constructs: async/await, generator, pulse etc.
- test stream / IO
- test TCP server / client
- test thread / thread_pool modules

## UDP socket

```ruby
socket = UDP.new

socket.on(:message) do |msg, info|
  puts "got #{msg} from #{info[:address]}:#{info[:port]}"
  socket.send("reply", **info)
end

socket.on(:listen) { puts "listening..." }

socket.bind(1234) # localhost port 1234
```

## DNS client

```ruby
ip_address = await DNS.lookup('google.com', 'A')
```

Prior art:

- https://github.com/alexdalitz/dnsruby
- https://github.com/eventmachine/eventmachine/blob/master/lib/em/resolver.rb
- https://github.com/gmodarelli/em-resolv-replace/blob/master/lib/em-dns-resolver.rb
- https://github.com/socketry/async-dns

### DNS server

```ruby
Server = import('../../lib/rubato/dns/server')

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
