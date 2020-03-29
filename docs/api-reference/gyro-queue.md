---
layout: page
title: Gyro::Queue
parent: API Reference
permalink: /api-reference/gyro-queue/
---
# Gyro::Queue

`Gyro::Queue` implements a polyphonic (fiber-aware) queue that can store 0 or
more items of any data types. Adding an item to the queue never blocks.
Retrieving an item from the queue will block if the queue is empty.
`Gyro::Queue` is both fiber-safe and thread-safe. This means multiple fibers
from multiple threads can concurrently interact with the same queue.
`Gyro::Queue` is used pervasively across the Polyphony code base for
synchronisation and fiber control.

## Instance methods

### #&lt;&lt;(object) → queue<br>#push(object) → queue

Adds an item to the queue.

### #clear → queue

Removes all items currently in the queue.

### #empty? → true or false

Returns true if the queue is empty. Otherwise returns false.

### #initialize

Initializes an empty queue.

### #shift → object<br>#pop → object

Retrieves an item from the queue. If the queue is empty, `#shift` blocks until
an item is added to the queue or until interrupted. Multiple fibers calling
`#shift` are served in a first-ordered first-served manner.

### #shift_each → [*object]<br>#shift_each({ block }) → queue

Removes and returns all items currently in the queue. If a block is given, it
will be invoked for each item.