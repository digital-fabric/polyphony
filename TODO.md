## 0.26 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - fix `IO_readpartial` to read from buffer
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.27 Working Sinatra application

- Pull out redis/postgres code, put into new `polyphony-xxx` gems
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

