## 0.32 Working Sinatra application

  - Work on exceptions:
    - Remove `Interrupt` base class for exceptions
    - Move value attribute code to `MoveOn` exception
    - Rename `MoveOn` to `Interrupt`

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

- Add option for setting the exception raised on cancelling using `#cancel_after`:

  ```ruby
  cancel_after(3, with_error: MyErrorClass) do
    do_my_thing
  end

  # or a RuntimeError with message
  cancel_after(3, with_error: 'Cancelling due to timeout') do
    do_my_thing
  end
  ```

- Test hypothetical situation 1:
  - fiber A sends a request to fiber B
  - fiber A waits for a message from B
  - fiber B terminates on a raised exception
  - What happens to fiber A? (it should get the exception)
    - The only way to achieve this is for B to
      - rescue the exception
      - send an error reply to A
      - reraise the exception:

      ```ruby
      def a(req)
        @b << [req, Fiber.current]
        receive
      end

      def b
        req, peer = receive
        result = handle_req(p)
        peer << result
      rescue Exception => e
        peer << e if peer
        raise e
      end
      ```

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
  - add explanation about async vs sync
  - discuss using `snooze` for ensuring responsiveness when executing CPU-bound work

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
require 'polyphony/dns'
server = Polyphony::DNS::Server.new do |transaction|
  transaction.questions.each do |q|
    respond(transaction, q[:domain], q[:resource_class])
  end
end

server.listen(port: 5300)
puts "listening on port 5300"
```

Prior art:

- https://github.com/socketry/async-dns

