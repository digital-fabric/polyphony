---
layout: page
title: Polyphony::Process
parent: API Reference
permalink: /api-reference/polyphony-process/
---
# Polyphony::Process

The `Polyphony::Process` module is used to watch child processes.

## Class Methods

### #watch(cmd = nil, { block })

Starts a child process, blocking until the child process terminates. If `#watch`
is interrupted before the child process terminates, the child process is sent a
`TERM` signal, and awaited. After 5 seconds, if the child has still not
terminated, it will be sent a `KILL` signal and awaited. This method is normally
used in conjunction with `#supervise` in order to supervise child processes.

If `cmd` is given, the child process is started using `Kernel#spawn` running a
shell command. If a block is given, the child process is started using
[`Polyphony#fork`](../polyphony/#fork-block---pid).

```ruby
spin { Polyphony::Process.watch('echo "Hello World"; sleep 1') }
supervise(restart: :always)
```
