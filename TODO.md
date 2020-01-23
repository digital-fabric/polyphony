## 0.28 Redo docs

- Return to linked list run queue (check performance)
- Reimplement thread pool
- Write about threads: FAQ, scheduling, etc
- Landing page like drawn in my notebook

- New copy:

  <div class="landing-hero">

  # Polyphony

  ### Fine-grained Concurrency for Ruby
  </div>

  <div class="landing-features">
  ## Focused on Developer Happiness

  Lorem ipsum

  ## Optimized for High Performane

  Lorem ipsum

  ## Designed for Interoperability

  Lorem ipsum

  ## A Growing Ecosystem

  </div>

- Offloading DB work to a worker thread (or thread pool), for example when using
    SQLite
  - Restore ThreadPool
  - Introduce concept of Worker, which acts more or less like Erlang's GenServer
    - it accepts an RPC invocation as a fiber message, sends back result
    - It can be used to do CPU-bound stuff on a separate thread while allowing a
      so-called "UI" thread to remain responsive by using fiber-aware
      concurrency.
- API for terminating a fiber from within the fiber. We already have:
  
  - `suspend`
  - `snooze`
  - `spin`
  - `spin_loop`
  
  And there's also:

  - `Fiber#schedule`
  - `Fiber#stop`
  - `Fiber#await`

  What we can possibly do is perhaps:

  - `resolve`
  - `terminate`

## 0.29 Multithreaded fiber scheduling - some rough corners

- `Gyro_schedule_fiber` - schedule using fiber's associated thread (store thread
  ref in fiber), instead of current thread
- Check why first call to `#sleep` returns too early in tests. Check the
  sleep behaviour in a spawned thread.

## 0.30 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.31 Sidekick

Plan of action:

- fork sidekiq, make adjustments to Polyphony code
- test performance
- proceed from there

## 0.32 Testing && Docs

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

## 0.33 Integration

## 0.34 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.35 Rails

- Rails?

## 0.36 DNS

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

