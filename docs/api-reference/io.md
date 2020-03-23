---
layout: page
title: ::IO
parent: API Reference
permalink: /api-reference/io/
---
# ::IO

[Ruby core IO documentation](https://ruby-doc.org/core-2.7.0/IO.html)

Polyphony reimplements a significant number of IO class and instance methods to
be fiber-aware. Polyphony also adds methods for accessing the associated event
watchers.

## Class Methods

## Instance methods

### #read_watcher → io_watcher

Returns the read watcher associated with the IO. The watcher is automatically
created and cached. The watcher is an instance of `Gyro::IO`. Normally this
method is not called directly from application code.

```ruby
def read_ten_chars(io)
  io.read_watcher.await
  io.read(10)
end
```

### #write_watcher → io_watcher

Returns the write watcher associated with the IO. The watcher is automatically
created and cached. The watcher is an instance of `Gyro::IO`. Normally this
method is not called directly from application code.