---
layout: page
title: Thread
nav_order: 2
parent: API Reference
permalink: /api-reference/thread/
# prev_title: Tutorial
# next_title: How Fibers are Scheduled
---
# Thread

[Ruby core Thread documentation](https://ruby-doc.org/core-2.7.0/Thread.html)

Polyphony enhances the core `Thread` class with APIs for switching and
scheduling fibers, and reimplements some of its APIs such as `Thread#raise`
using fibers which, incidentally, make it safe.

Each thread has its own run queue and its own event selector. While running
multiple threads does not result in true parallelism in MRI Ruby, sometimes
multithreading is inevitable, for instance when using third-party gems that
spawn threads, or when calling blocking APIs that are not fiber-aware.

## Class Methods

## Instance methods

### #&lt;&lt;(object) → fiber<br>#send(object) → fiber

Sends a message to the thread's main fiber. For further details see
[`Fiber#<<`](../fiber/#object--fibersendobject--fiber).

### #fiber_scheduling_stats → stats

Returns statistics relating to fiber scheduling for the thread with the
following entries:

- `:scheduled_fibers` - number of fibers currently in the run queue
- `:pending_watchers` - number of currently pending event watchers

### #join → object<br>#await → object

Waits for the thread to finish running. If the thread has terminated with an
uncaught exception, it will be reraised in the context of the calling fiber. If
no excecption is raised, returns the thread's result.

```ruby
t = Thread.new { sleep 1 }
t.join
```

### #main_fiber → fiber

Returns the main fiber for the thread.

### #result → object

Returns the result of the thread's main fiber.

```ruby
t = Thread.new { 'foo' }
t.join
t.result #=> 'foo'
```

### #switch_fiber

invokes a switchpoint, selecting and resuming the next fiber to run. The
switching algorithm works as follows:

- If the run queue is not empty, conditionally run the event loop a single time
  in order to prevent event starvation when there's always runnable fibers
  waiting to be resumed.
- If the run queue is empty, run the event loop until a fiber is put on the run
  queue.
- Switch to the first fiber in the run queue.

This method is normally not called directly by the application. Calling
`Thread#switch_fiber` means the current fiber has no more work to do and would
like yield to other fibers. Note that if the current fiber needs to resume at a
later time, it should be scheduled before calling `Thread#switch_fiber`.

```ruby
# schedule current fiber to be resumed later
Fiber.current.schedule

# switch to another fiber
Thread.current.switch_fiber

# the fiber is resumed
resume_work
```