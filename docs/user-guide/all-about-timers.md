---
layout: page
title: All About Timers
nav_order: 1
parent: User Guide
permalink: /user-guide/all-about-timers/
---
# All About Timers

Timers form a major part of writing dynamic concurrent programs. They allow
programmers to create delays and to perform recurring operations with a
controllable frequency. Crucially, they also enable the implementation of
timeouts, which are an important aspect of concurrent programming.

## Waiting for timers

Polyphony implements timers through the `Gyro::Timer` class, which encapsulates
libev timer watchers. Using `Gyro::Timer` you can create both one-time and
recurring timers:

```ruby
# Create a one-time timer
one_time = Gyro::Timer.new(1, 0)

# Create a recurring timer
```