---
layout: page
title: Polyphony::ThreadPool
parent: API Reference
permalink: /api-reference/polyphony-threadpool/
---
# Polyphony::ThreadPool

`Polyphony::ThreadPool` implements a general purpose thread pool, normally used
for the execution of non-fiber aware operations, such as C-extension based
third-party libraries or other system call blocking APIs. The Polyphony
implementation of a thread pool allows limiting the number of threads used for
performing a recurring operation across one or more fibers.

A default thread pool is available for quick access to this feature.

## Class methods

### #process({ block }) → object

Runs the given block on the default thread pool. The default pool will be
created on the first call to `#process`. This method will block until the
operation has completed. The return value is that of the given block. Any
uncaught exception will be propagated to the callsite.

```ruby
result = Polyphony::ThreadPool.process { lengthy_op }
```

## Instance methods

### #busy? → true or false

Returns true if operations are currently being run on the thread pool.

### cast({ block }) → pool

Runs the given block on one of the threads in the pool in a fire-and-forget
manner, without waiting for the operation to complete. Using `#cast` to run an
operation means there's no way of knowing if the operation has completed or if
any exception has been raised, other than inside the block.

```ruby
my_pool.cast { puts 'Hello world' }
do_something_else
```

### #initialize(size = Etc.nprocessors)

Initializes a new instance of `Polyphony::ThreadPool` with the given maximum
number of threads. The default size is the number of available processors
(number of CPU cores).

```ruby
my_pool = Polyphony::ThreadPool.new(3)
```

### #process({ block }) → object

Runs the given block on one of the threads in the thread pool and blocks until
the operation has completed. The return value is that of the given block. Any
uncaught exception will be propagated to the callsite.

```ruby
pool = Polyphony::ThreadPool.new(3)
result = pool.process { lengthy_op }
```
