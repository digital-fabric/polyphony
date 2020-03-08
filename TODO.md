- Debugging
  - Eat your own dogfood: need a good tool to check what's going on when some
    test fails
  - Needs to work with Pry (can write perhaps an extension for pry)
  - First impl in Ruby using `TracePoint` API
  - Mode of operation:
    - Debugger runs on separate thread
    - The `TracePoint` handler passes control to the debugger thread, and waits
      for reply (probably using Fiber messages)
  - Step over should return on the next line *for the same fiber*
  - The event loop (all event loops?) should be suspended so timers are adjusted
    accordingly, so on control passing to debugger we:

    - call `ev_suspend()` for main thread ev_loop
    - prompt and wait for input from user
    - call `ev_resume()` for main thread ev_loop
    - process user input

    (We need to verify than `ev_suspend/resume` works for an ev_loop that's not
    currently running.)
  - Allow inspection of fiber tree, thread's run queue, fiber's scheduled values etc.

  - UI
    - `Kernel#breakpoint` is used to break into the debugger while running code

      ```ruby
      def test_sleep
        f = spin { sleep 10 }
        breakpoint
        ...
      end
      ```

      Hitting the breakpoint will show the current location in the source code
      (with few lines before and after), and present a prompt for commands.
    
    - commands:
      - `step` / `up` / `skip` / `continue` etc. - step into, step out, step over, run
      - `switch` - switch fiber
        - how do we select a fiber?
          - from a list?
          - from an expression: `Fiber.current.children`
          - maybe just `select f1` (where f1 is a local var)

## 0.33 Some more API work, more docs

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

## 0.34 Sinatra / Sidekiq

- sintra app with database access (postgresql)

- sidekiq: Plan of action
  - see if we can get by just writing an adapter
  - if not, fork sidekiq, make adjustments to Polyphony code
  - test performance
  - proceed from there

## 0.35 Testing && Docs

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

## 0.36 Integration

## 0.37 Real IO#gets and IO#read

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

## 0.38 Rails

- Rails?

## 0.39 DNS

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

