---
layout: page
title: Gyro
parent: API Reference
permalink: /api-reference/gyro/
---
# Gyro

`Gyro` is the subsystem in charge of the low-level functionality in Polyphony.
It contains all of the different event watcher classes, as well as other
low-level constructs such as `Gyro::Queue`, a fiber-aware queue implementation,
used pervasively across the Polyphony code base.

While most Polyphony-based applications do not normally need to interact
directly with the `Gyro` classes, more advanced applications and libraries may
use those classes to enhance Polyphony and create custom concurrency patterns.

## Classes

- [`Gyro::Async`](../gyro-async/) - async event watcher
- [`Gyro::Child`](../gyro-child/) - child process event watcher
- [`Gyro::IO`](../gyro-io/) - IO event watcher
- [`Gyro::Queue`](../gyro-queue/) - fiber-aware queue
- [`Gyro::Signal`](../gyro-signal/) - signal event watcher
- [`Gyro::Timer`](../gyro-timer/) - timer event watcher
