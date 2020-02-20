## 0.31 Working Sinatra application

- Resolve a race condition relating to signals
  - An `INT` signal is trapped
  - The corresponding exception `Interrupt` is scheduled for the fiber
  - But the runqueue already contains other fibers, which are scheduled before
    the interrupt fiber, so they will run first
  - One of the runnable fibers that are ran schedules the interrupted fiber,
    again, with some other non-exception value
  - The `Interrupt` exception magically disappears!

  Possible solutions:

  * When scheduling a fiber, check if it's already scheduled with an exception.
    If it is, don't change the value. The problem with this approach is that we
    have to reset the resume value stored for the fiber.
  * Add an API for scheduling a fiber by putting it in *front* of the runqueue.
    This API would be used execlusively (at least for the time being) by the
    signal traps. This should eliminate the race condition.


- Accept rate/interval in `spin_loop` and `spin_worker_loop`:

  ```ruby
  spin_loop(10) { ... } # 10 times per second
  spin_loop(rate: 10) { ... } # 10 times per second
  spin_loop(interval: 10) { ... } # once every ten seconds
  ```

- Docs
  - landing page:
    - links to the interesting stuff
      - concurrency overview
      - faq
      - benchmarks
  - explain difference between `sleep` and `suspend`
  - concurrency overview: add explanation about async vs sync

- move all adapters into polyphony/adapters

- Check why first call to `#sleep` returns too early in tests. Check the
  sleep behaviour in a spawned thread.
- sintra app with database access (postgresql)

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

