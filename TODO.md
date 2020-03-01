- Fiber supervision
  - can a fiber be restarted?
    - Theoretically, we can take the same block and rerun it under a different
      fiber
  - (restart) strategy (taken from Erlang):
    - `:one_for_one`: if a child terminates, it is restarted
    - `:one_for_all`: if a child terminates, all other children are terminated,
      then all are restarted
    - `:simple_on_for_one`: same as `:one_for_one` except all children are
      identical (run the same block)
  - I'm not so sure this kind of supervision is what we need. We can envision
    an API such as the following:

    ```ruby
    spin {
      spin { do_a }
      spin { do_b }
      supervise(restart: :none, shutdown: :terminate)
    }
    ```

  - The default for `#supervise` should be:
    - wait for all fibers to terminate
    - propagate exceptions
    - no restart
  
  - `#supervise` could also take a block:

    ```ruby
    supervise do |fiber, error|
      # this block is called when a fiber is terminated, letting the developer
      # decide how to react.

      # We can propagate the error
      raise error if error

      # We can restart the fiber (the respun fiber will have the same parent,
      # the same caller location, the same tag)
      fiber.respin # TODO: implement Fiber#respin
    end
    ```

## 0.32 Working Sinatra application

- Docs
  - landing page:
    - links to the interesting stuff
      - concurrency overview
      - faq
      - benchmarks
  - explain difference between `sleep` and `suspend`
  - add explanation about async vs sync
  - discuss using `snooze` for ensuring responsiveness when executing CPU-bound work

- Check why first call to `#sleep` returns too early in tests. Check the
  sleep behaviour in a spawned thread.

## 0.33 Sinatra / Sidekiq

- sintra app with database access (postgresql)

- sidekiq: Plan of action
  - see if we can get by just writing an adapter
  - if not, fork sidekiq, make adjustments to Polyphony code
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

### Work on API

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
