---
layout: page
title: Polyphony
parent: API Reference
permalink: /api-reference/polyphony/
---
# Polyphony

The `Polyphony` module acts as a namespace containing general Polyphony
functionalities.

## Class Methods

### #emit_signal_exception(exception, fiber = Thread.main.main_fiber) → thread

Emits an exception to the given fiber from a signal handler.

### #fork({ block }) → pid

Forks a child process running the given block. Due to the way Ruby implements
fibers, along with how signals interact with them, Polyphony-based applications
should use `Polyphony#fork` rather than `Kernel#fork`. In order to continue
handling fiber scheduling and signal handling correctly, the child process does
the following:

- A new fiber is created using `Fiber#new` and control is transferred to it.
- Notify the event loop that a fork has occurred (by calling `ev_loop_fork`).
- Setup the current fiber as the main thread's main fiber.
- Setup fiber scheduling for the main thread.
- Install fiber-aware signal handlers for the `TERM` and `INT` signals.
- Run the block.
- Correctly handle uncaught exceptions, including `SystemExit` and `Interrupt`.

### #watch_process(cmd = nil, { block })

Alternative for [`Polyphony::Process.watch`](../polyphony-process/#watchcmd--nil--block-).
