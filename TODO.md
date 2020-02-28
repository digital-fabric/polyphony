## 0.32 Working Sinatra application

  - Introduce mailbox limiting:
    - add API for limiting mailbox size:

      ```ruby
      Fiber.current.mailbox_limit = 1000
      ```

    - Add the limit for `Gyro::Queue`

      ```ruby
      Gyro::Queue.new(1000)
      ```

    - Pushing to a limited queue will block if limit is reached

  - Introduce selective receive:

    ```ruby
    # returns (or waits for) the first message for which the block returns true
    (_, item) = receive { |msg| msg.first == ref }
    ```

    Possible implementation:

    ```ruby
    def receive
      return @mailbox.shift unless block_given?
      
      loop
        msg = @mailbox.shift
        return msg if yield(msg)

        # message didn't match condition, put it back in queue
        @mailbox.push msg
      end
    end
    ```

- Test hypothetical situation 1:
  - fiber A sends a request to fiber B
  - fiber B terminates on a raised exception
  - What happens to fiber A? (it should get the exception)

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

## 0.33 Sidekick

Plan of action:

- fork sidekiq, make adjustments to Polyphony code
- test performance
- proceed from there

## 0.34 Testing && Docs

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

## 0.35 Integration

## 0.36 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.37 Rails

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

