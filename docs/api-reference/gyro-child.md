---
layout: page
title: Gyro::Child
parent: API Reference
permalink: /api-reference/gyro-child/
---
# Gyro::Child

`Gyro::Child` encapsulates a libev [child
watcher](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod#code_ev_child_code_watch_out_for_pro),
used for waiting for a child process to terminate. A `Gyro::Child` watcher
instance can be used for low-level control of child processes, instead of using
more high-level APIs such `Process.wait` etc.

## Instance methods

### #await → [pid, exitcode]

Blocks the current thread until the watcher is signalled. The return value is an
array containing the child's pid and the exit code.

```ruby
pid = Polyphony.fork { sleep 1 }
Gyro::Child.new(pid).await #=> [pid, 0]
```

### #initialize(pid)

Initializes the watcher instance with the given pid
