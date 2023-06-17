# @title All About Cancellation: How to Stop Concurrent Operations

# All About Cancellation: How to Stop

## The Problem of Cancellation

Being able to cancel an operation is a crucial aspect of concurrent programming.
When you have multiple operations going on at the same time, you want to be able
to stop an operation in certain circumstances. Imagine sending a an HTTP request
to some server, and waiting for it to respond. We can wait forever, or we can
use some kind of mechanism for stopping the operation and declaring it a
failure. This mechanism, which is generally called cancellation, plays a crucial
part in how Polyphony works. Let's examine how operations are cancelled in
Polyphony.

## Cancellation in Polyphony

In Polyphony, every operation can be cancelled in the same way, using the same
APIs. Polyphony provides multiple APIs that can be used to stop an ongoing
operation, but the underlying mechanism is always the same: the fiber running
the ongoing operation is scheduled with an exception.

Let's revisit how fibers are run in Polyphony (this is covered in more detail in
the overview document). When a waiting fiber is ready to continue, it is
scheduled with the result of the operation which it was waiting for. If the
waiting fiber is scheduled with an exception *before* the operation it is
waiting for is completed, the operation is stopped, and the exception is raised
in the context of the fiber once it is switched to. What this means is that any
fiber waiting for a long-running operation to complete can be stopped at any
moment, with Polyphony taking care of actually stopping the operation, whether
it is reading from a file, or from a socket, or waiting for a timer to elapse.

On top of this general mechanism of cancellation, Polyphony provides
cancellation APIs with differing semantics that can be employed by the
developer. For example, `move_on_after` can be used to stop an operation after a
timeout without raising an exception, while `cancel_after` can be used to raise
an exception that must be handled. There's also the `Fiber#restart` API which,
as its name suggests, allows one to restart any fiber, which might be very
useful for retrying complex operations.

Let's examine how a concurrent operation is stopped in Polyphony:

```ruby
sleeper = spin { sleep 1 }
sleep 0.5
sleeper.raise 'Foo'
```

In the example above, we spin up a fiber that sleeps for 1 second, we then sleep
for half a second, and cancel `sleeper` by raising an exception in its context.
This causes the sleep operation to be cancelled and the fiber to be stopped. The
exception is further propagated to the context of the main fiber, and the
program finally exits with an exception message.

Another way to stop a concurrent operation is to use the `Fiber#move_on` method,
which causes the fiber to stop, but without raising an exception:

```ruby
sleeper = spin { sleep 1; :foo }
sleep 0.5
sleeper.move_on :bar
result = sleeper.await #=> :bar
```

Using `Fiber#move_on`, we avoid raising an exception which then needs to be
rescued, and instead cause the fiber to stop, with its return value being the
value given to `Fiber#move_on`. In the code above, the fiber's result will be
set to `:bar` instead of `:foo`.

## Using Timeouts

Timeouts are probably the most common reason for cancelling an operation. While
different Ruby gems provide their own APIs and mechanisms for setting timeouts
(core Ruby has also recently introduced timeout settings for IO operations),
Polyphony provides a uniform interface for stopping *any* long-running operation
based on a timeout, using either the core ruby `Timeout` class, or the
`move_on_after` and `cancel_after` that Polyphony provides.

Before we discuss the different timeout APIs, we can first explore how to create
a timeout mechanism from scratch in Polyphony:

```ruby
class MyTimeoutError < RuntimeError
end

def with_timeout(duration)
  timeout_fiber = spin do
    sleep duration
    raise MyTimeoutError
  end
  yield
ensure
  timeout_fiber.stop # this is the same as timeout_fiber.move_on
end

# Usage example:
with_timeout(5) { sleep 1; :foo } #=> :foo
with_timeout(5) { sleep 10; :bar } #=> MyTimeoutError raised!
```

In the code above, we create a `with_timeout` method that takes a duration
argument. It starts by spinning up a fiber that will sleep for the given
duration, then raise a custom exception. It then runs the given block by calling
`yield`. If the given block stops running before the timeout, it exists
normally, not before making sure to stop the timeout fiber. If the given block
runs longer than the timeout, the exception raised by the timeout fiber will be
propagated to the fiber running the block, causing it to be stopped.

Now that we have an idea of how we can construct timeouts, let's look at the
different timeout APIs included in Polyphony:

```ruby
# Timeout without raising an exception
move_on_after(5) { ... }

# Timeout without raising an exception, returning an arbitrary value
move_on_after(5, with_value: :foo) { ... } #=> :foo (in case of a timeout)

# Timeout raising an exception
cancel_after(5) { ... } #=> raises a Polyphony::Cancel exception

# Timeout raising a custom exception
cancel_after(5, with_exception: MyExceptionClass) { ... } #=> raises the given exception

# Timeout using the Timeout API
Timeout.timeout(5) { ... } #=> raises Timeout::Error
```

## Resetting Ongoing Operations

In addition to offering a uniform API for cancelling operations and setting
timeouts, Polyphony also allows you to reset, or restart, ongoing operations.
Let's imagine an active search feature that shows the user search results while
they're typing their search term. How we go about implementing this? We would
like to show the user search results, but if the user hits another key before
the results are received from the database, we'd like to cancel the operation
and relaunch the search. Let's see how Polyphony let's us do this:

```ruby
searcher = spin do
  peer, term = receive
  results = get_search_results_from_db(term)
  peer << results
end

def search_term_updated(term)
  spin do
    searcher.restart
    searcher << [Fiber.current, term]
    results = receive
    update_search_results(results)
  end
end
```

In the example above we use fiber message passing in order to communicate
between two concurrent operations. Each time `search_term_updated` is called, we
*restart* the `searcher` fiber, send the term to it, wait for the results and
them update them in the UI.

## Resettable Timeouts

Here's another example of restarting: we have a TCP server that accepts
connection but would like to close connections after one minute of inactivity.
We can use a timeout for that, but each time we receive data from the client, we
need to reset the timeout. Here's how we can do this:

```ruby
def handle_connection(conn)
  timeout = spin do
    sleep 60
    raise Polyphony::Cancel
  end
  conn.recv_loop do |msg|
    timeout.reset # same as timeout.restart
    handle_message(msg)
  end
rescue Polyphony::Cancel
  puts 'Closing connection due to inactivity!'
ensure
  timeout.stop
end

server.accept_loop { |conn| handle_connection(conn) }
```

In the code above, we create a timeout fiber that sleeps for one minute, then
raises an exception. We then run a loop waiting for messages from the client,
and each time a message arrives we reset the timeout. In fact, the standard
`#move_on_after` and `#cancel_after` APIs also propose a way to reset timeouts.
Let's examine how to do just that:

```ruby
def handle_connection(conn)
  cancel_after(60) do |timeout|
    conn.recv_loop do |msg|
      timeout.reset
      handle_message(msg)
    end
  end
rescue Polyphony::Cancel
  puts 'Closing connection due to inactivity!'
end

server.accept_loop { |conn| handle_connection(conn) }
```

Here, instead of hand-rolling our own timeout mechanism, we use `#cancel_after`
but give it a block that takes an argument. When the block is called, this
argument is actually the timeout fiber that `#cancel_after` spins up, which lets
us reset it just like in the example before. Also notice how we don't need to
cleanup the timeout in the ensure block, as `#cancel_after` takes care of it by
itself.
