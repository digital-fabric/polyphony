- Check segfault when doing lots of `cancel_after` calls

- Override stock `SizedQueue` impl with Queue with capacity

- Add support for `break` and `StopIteration` in all loops (with tests)

- Change `IO#gets` to use `String#split` to cut into lines, much faster (see
  examples/performance/line_splitting.rb)

- More tight loops
  - `IO#gets_loop`, `Socket#gets_loop`, `OpenSSL::Socket#gets_loop` (medium effort)
  - `Fiber#receive_loop` (very little effort, should be implemented in C)


- Add `Backend#splice`, `Backend#splice_loop` for implementing stuff like proxying:

  ```ruby
  def two_way_proxy(socket1, socket2)
    backend = Thread.current.backend
    f1 = spin { backend.splice_loop(socket1, socket2) }
    f2 = spin { backend.splice_loop(socket2, socket1) }
    Fiber.await(f1, f2)
  end
  ```

- Graceful shutdown again:
  - What happens to children when doing a graceful shutdown?
  - What are the implications of passing graceful shutdown flag to children?
  - What about errors while doing a graceful shutdown?
  - What about graceful restarts?
  - Some interesting discussions:
    - https://trio.discourse.group/search?q=graceful%20shutdown
    - https://github.com/python-trio/trio/issues/147
    - https://github.com/python-trio/trio/issues/143
    - https://trio.discourse.group/t/graceful-shutdown/93/2
    - https://250bpm.com/blog:146/
    - https://www.rodrigoaraujo.me/posts/golang-pattern-graceful-shutdown-of-concurrent-events/
    - https://github.com/tj/go-gracefully
  - `Fiber#finalize_children` should pass graceful shutdown flag to children
  - A good use case is an HTTP server that on graceful shutdown:
    - stops listening
    - waits for all ongoing requests to finish, optionally with a timeout

## Roadmap for Polyphony 1.0

- check integration with rb-inotify

- Improve `#supervise`. It does not work as advertised, and seems to exhibit an
  inconsistent behaviour (see supervisor example).

- Add test that mimics the original design for Monocrono:
  - 256 fibers each waiting for a message
  - When message received do some blocking work using a `ThreadPool`
  - Send messages, collect responses, check for correctness

- io_uring
  - Use playground.c to find out why we when submitting and waiting for
    completion in single syscall signals seem to be blocked until the syscall
    returns. Is this a bug in io_uring/liburing?

-----------------------------------------------------

- Add `Backend#splice(in, out, nbytes)` API
- Adapter for io/console (what does `IO#raw` do?)
- Adapter for Pry and IRB (Which fixes #5 and #6)
- allow backend selection at runtime
- Debugging
  - Eat your own dogfood: need a good tool to check what's going on when some
    test fails
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







- Docs
  - landing page:
    - links to the interesting stuff
      - benchmarks
  - explain difference between `sleep` and `suspend`
  - discuss using `snooze` for ensuring responsiveness when executing CPU-bound work


### Some more API work, more docs

- sintra app with database access (postgresql)

- sidekiq: Plan of action
  - see if we can get by just writing an adapter
  - if not, fork sidekiq, make adjustments to Polyphony code
  - test performance
  - proceed from there


### Sinatra / Sidekiq

- Pull out redis/postgres code, put into new `polyphony-xxx` gems

### Testing && Docs

- More tests
- Implement some basic stuff missing:
  - override `IO#eof?` since it too reads into buffer
  - real `IO#gets` (with buffering)
  - `IO#read` (read to EOF)
  - `IO.foreach`
  - `Process.waitpid`

### Quic / HTTP/3

- Python impl: https://github.com/aiortc/aioquic/
- Go impl: https://github.com/lucas-clemente/quic-go

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

