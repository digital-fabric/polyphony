## 0.27 Multithreaded scheduling

- Verify performance, compare to single-threaded version (on `master`)
- Write tests

## 0.28 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.29 Sidekick

Plan of action:

- fork sidekiq, make adjustments to Polyphony code
- test performance
- proceed from there

## 0.30 Testing && Docs

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

## 0.31 Integration

## 0.32 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.32 Support for multithreaded apps

- Move fiber scheduling to the `Thread` class
- Gyro selector conforming to the selector interface:
  
  ```ruby
  class Selector
    def wait
  end
  ```

- Better separation between 

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

