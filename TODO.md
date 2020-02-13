## 0.30 Multithreaded fiber scheduling - some rough corners

- Implement nested fibers
  - Add tests:
    - `Fiber#await` from multiple fibers at once
      (reimplement `Fiber#await` using `Fiber#when_done`)

## 0.31 Working Sinatra application

- Accept rate/interval in `spin_loop` and `spin_worker_loop`:

  ```ruby
  spin_loop(10) { ... } # 10 times per second
  spin_loop(rate: 10) { ... } # 10 times per second
  spin_loop(interval: 10) { ... } # once every ten seconds
  ```

- Docs: explain difference between `sleep` and `suspend`
- Check why first call to `#sleep` returns too early in tests. Check the
  sleep behaviour in a spawned thread.
- app with database access (postgresql)
- benchmarks!

## 0.32 Sidekick

Plan of action:

- fork sidekiq, make adjustments to Polyphony code
- test performance
- proceed from there

## 0.33 Testing && Docs

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

## 0.34 Integration

## 0.35 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.36 Rails

- Rails?

## 0.37 DNS

### DNS client

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

