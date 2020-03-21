- Would it be possible to spin up a fiber on another thread?
  
  The use case is being able to supervise fibers that run on separate threads.
  This might be useful for distributing jobs (such as handling HTTP connections)
  over multiple threads.

  For this we need:

  - A way to communicate to a thread that it needs to spin up a fiber, the
    simplest solution is to start a fiber accepting spin requests for each
    thread (in `Thread#initialize`).
  - An API:

    ```ruby
    spin(on_thread: thread) { do_something_important }
    ```

  An alternative is to turn the main fiber of spawned threads into a child of
  the spawning fiber. But since a lot of people might start threads without any
  regard to fibers, it might be better to implement this in a new API. An
  example of the top of my head for threads that shouldn't be children of the
  spawning fiber is our own test helper, which kills all child fibers after each
  test. MiniTest has some threads it spawns for running tests in parallel, and
  we don't want to stop them after each test!

  So, a good solution would be:

  ```ruby
  t = Thread.new { do_stuff }
  t.parent_fiber = Fiber.current
  # or otherwise:
  Fiber.current.add_child_fiber(t.main_fiber)
  ```

## 0.33 Some more API work, more docs

- Debugging
  - Eat your own dogfood: need a good tool to check what's going on when some
    test fails
  - Needs to work with Pry (can write perhaps an extension for pry)
  - First impl in Ruby using `TracePoint` API
  - Mode of operation:
    - Two parts: tracer and controller
      - The tracer keeps state
      - The controller interacts with the user and tells the tracer what to do
      - Tracer and controller interact using fiber message passing
      - The controller lives on a separate thread
      - The tracer invokes the controller at the appropriate point in time
        according to the state. For example, when doing a `next` command, the
        tracer will wait for a `:line` event to occur within the same stack
        frame, or for the frame to be popped on a `:return` event, and only then
        will it invoke the controller.
      - While invoking the controller and waiting for its reply, the tracer
        optionally performs a fiber lock in order to prevent other fibers from
        advancing (the fiber lock is the default mode).
    - The tracer's state is completely inspectable

      ```ruby
      PolyTrace.state
      PolyTrace.current_fiber
      PolyTrace.call_stack
      ```

    - Modes can be changed using an API, e.g.

      ```ruby
      PolyTrace.fiber_lock = false
      ```

    - Fibers can be interrogated using an API, or perhaps using some kind of
      Pry command...

    - Normal mode of operation is fiber modal, that is, trace only the currently
      selected fiber. The currently selected fiber may be changed upon breakpoint

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

- Allow locking the scheduler on to one fiber
  - Add instance var `@fiber_lock`
  - API is `Thread#fiber_lock` which sets the fiber_lock instance varwhile
    running the block:

    ```ruby
    def debug_prompt
      Thread.current.fiber_lock do
        ...
      end
    end
    ```
  - When `@fiber_lock` is set, it is considered as the only one in the run
    queue:

    ```c
    VALUE fiber_lock = rb_ivar_get(self, ID_ivar_fiber_lock);
    int locked = fiber_lock != Qnil;

    while (1) {
      next_fiber = locked ? fiber_lock : rb_ary_shift(queue);
      ...
    }
    ```






- Add pretty API for trapping signals. Right now Polyphony traps `INT` and
  `TERM` by doing:

  ```ruby
  Thread.current.break_out_of_ev_loop(Thread.main.main_fiber, exception)
  ```

  We can add a pretty API for this, maybe:

  ```ruby
  Polyphony.emit_signal_exception(exception)

  # where
  def Polyphony.emit_signal_exception(exception, fiber = Thread.main.main_fiber)
    Thread.current.break_out_of_ev_loop(fiber, exception)
  end
  ```


- Process supervisor - life cycle hooks

  ```ruby
  # general solution for fiber supervision
  def supervision_event_handler(event, fiber)
    ...
  end

  spin do
    spin { do_stuff }
    supervise do |event, fiber|

    end
  end

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

