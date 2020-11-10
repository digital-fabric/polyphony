* Reimplement `move_on_after`, `cancel_after`, `Timeout.timeout` using
  `Backend#timeout` (avoids creating canceller fiber for most common use case)
* Implement `Backend#timeout` API
* Implemented capped queues

## 0.46.1

* Add `TCPServer#accept_loop`, `OpenSSL::SSL::SSLSocket#accept_loop` method
* Fix compilation error on MacOS (#43)
* Fix backtrace for `Timeout.timeout`
* Add `Backend#timer_loop`

## 0.46.0

* Implement [io_uring backend](https://github.com/digital-fabric/polyphony/pull/44)

## 0.45.5

* Fix compilation error (#43)
* Add support for resetting move_on_after, cancel_after timeouts
* Optimize anti-event starvation polling
* Implement optimized runqueue for better performance
* Schedule parent with priority on uncaught exception
* Fix race condition in `Mutex#synchronize` (#41)

## 0.45.4

* Improve signal trapping mechanism

## 0.45.3

* Don't swallow error in `Process#kill_and_await`
* Add `Fiber#mailbox` attribute reader
* Fix bug in `Fiber.await`
* Implement `IO#getc`, `IO#getbyte`

## 0.45.2

* Rewrite `Fiber#<<`, `Fiber#await`, `Fiber#receive` in C

## 0.45.1

* Fix Net::HTTP compatibility
* Fix fs adapter
* Improve performance of IO#puts
* Mutex#synchronize
* Fix Socket#connect
* Cleanup code
* Improve support for Ruby 3 keyword args

## 0.45.0

* Cleanup code
* Rename `Agent` to `Backend`
* Implement `Polyphony::ConditionVariable`
* Fix Kernel.system

## 0.44.0 2020-07-25

* Fix reentrant `ResourcePool` (#38)
* Add `ResourcePool#discard!` (#35)
* Add `Mysql2::Client` and `Sequel::ConnectionPool` adapters (#35)
* Reimplement `Kernel.trap` using `Fiber#interject`
* Add `Fiber#interject` for running arbitrary code on arbitrary fibers (#39)

## 0.43.11 2020-07-24

* Dump uncaught exception info for forked process (#36)
* Add additional socket config options (#37)
  - :reuse_port (`SO_REUSEPORT`)
  - :backlog (listen backlog, default `SOMAXCONN`)
* Fix possible race condition in Queue#shift (#34)

## 0.43.10 2020-07-23

* Fix race condition when terminating fibers (#33)
* Fix lock release in `Mutex` (#32)
* Virtualize agent interface
* Implement `LibevAgent_connect`

## 0.43.9 2020-07-22

* Rewrite `Channel` using `Queue`
* Rewrite `Mutex` using `Queue`
* Reimplement `Event` in C to prevent cross-thread race condition
* Reimplement `ResourcePool` using `Queue`
* Implement `Queue#size`

## 0.43.8 2020-07-21

* Rename `LibevQueue` to `Queue`
* Reimplement Event using `Agent#wait_event`
* Improve Queue shift queue performance
* Introduce `Agent#wait_event` API for waiting on asynchronous events
* Minimize `fcntl` syscalls in IO operations 

## 0.43.7 2020-07-20

* Fix memory leak in ResourcePool (#31)
* Check and adjust file position before reading (#30)
* Minor documentation fixes

## 0.43.6 2020-07-18

* Allow brute-force interrupting with second Ctrl-C
* Fix outgoing SSL connections (#28)
* Improve Fiber#await_all_children with many children
* Use `writev` for writing multiple strings
* Add logo (thanks [Gerald](https://webocube.com/)!)

## 0.43.5 2020-07-13

* Fix `#read_nonblock`, `#write_nonblock` for `IO` and `Socket` (#27)
* Patch `Kernel#p`, `IO#puts` to issue single write call
* Add support for multiple arguments in `IO#write` and `LibevAgent#write`
* Use LibevQueue for fiber run queue
* Reimplement LibevQueue as ring buffer

## 0.43.4 2020-07-09

* Reimplement Kernel#trap
* Dynamically allocate read buffer if length not given (#23)
* Prevent CPU saturation on infinite sleep (#24)

## 0.43.3 2020-07-08

* Fix behaviour after call to `Process.daemon` (#8)
* Replace core `Queue` class with `Polyphony::Queue` (#22)
* Make `ResourcePool` reentrant (#1)
* Accept `:with_exception` argument in `cancel_after` (#16)

## 0.43.2 2020-07-07

* Fix sending Redis commands with array arguments (#21)

## 0.43.1 2020-06

* Fix compiling C-extension on MacOS (#20)

## 0.43 2020-07-05

* Add IO#read_loop
* Fix OpenSSL extension
* More work on docs

## 0.42 2020-07-03

* Improve documentation
* Fix backtrace on SIGINT
* Implement LibevAgent#accept_loop, #read_loop
* Move ref counting from thread to agent
* Short circuit switchpoint if continuing with the same fiber
* Always do a switchpoint in #read, #write, #accept

## 0.41 2020-06-27

* Introduce System Agent design, remove all `Gyro` classes

## 0.40 2020-05-04

* More improvements to stability after fork

## 0.38 2020-04-13

* Fix post-fork segfault if parent process has multiple threads with active watchers

## 0.37 2020-04-07

* Explicitly kill threads on exit to prevent possible segfault
* Remove Modulation dependency

## 0.36 2020-03-31

* More docs
* More C code refactoring
* Fix freeing for active child, signal watchers

## 0.35 2020-03-29

* Rename `Fiber#cancel!` to `Fiber#cancel`
* Rename `Gyro::Async#signal!` to `Gyro::Async#signal`
* Use `Fiber#auto_watcher` in thread pool, thread extension
* Implement `Fiber#auto_io` for reusing IO watcher instances
* Refactor C code

## 0.34 2020-03-25

* Add `Fiber#auto_watcher` mainly for use in places like `Gyro::Queue#shift`
* Refactor C extension
* Improved GC'ing for watchers
* Implement process supervisor (`Polyphony::ProcessSupervisor`)
* Improve fiber supervision
* Fix forking behaviour
* Use correct backtrace for fiber control exceptions
* Allow calling `move_on_after` and `cancel_after` without block

## 0.33 2020-03-08

* Implement `Fiber#supervise` (WIP)
* Add `Fiber#restart` API
* Fix race condition in `Thread#join`, `Thread#raise` (#14)
* Add `Exception#source_fiber` - references the fiber in which an uncaught
  exception occurred

## 0.32 2020-02-29

* Accept optional throttling rate in `#spin_loop`
* Remove CancelScope
* Allow spinning fibers from a parent fiber other than the current
* Add `#receive_pending` global API.
* Prevent race condition in `Gyro::Queue`.
* Improve signal handling - `INT`, `TERM` signals are now always handled in the
  main fiber
* Fix adapter requires (redis and postgres)

## 0.31 2020-02-20

* Fix signal handling race condition (#13)
* Move adapter code into polyphony/adapters
* Fix spin_loop caller, add tag parameter

## 0.30 2020-02-04

* Add support for awaiting a fiber from multiple monitor fibers at once
* Implemented child fibers
* Fix TERM and INT signal handling (#11)
* Fix compiling on Linux
* Do not reset runnable value in Gyro_suspend (prevents interrupting timers)
* Don't snooze when stopping a fiber
* Fix IO#read for files larger than 8KB (#10)
* Fix fiber messaging in main fiber
* Prevent signalling of inactive async watcher
* Better fiber messaging

## 0.29 2020-02-02

* Pass SignalException to main fiber
* Add (restore) default thread pool
* Prevent race condition in Thread#join
* Add support for cross-thread fiber scheduling
* Remove `#defer` global method
* Prevent starvation of waiting fibers when using snooze (#7)
* Improve tracing
* Fix IRB adapter

## 0.28 2020-01-27

* Accept block in Supervisor#initialize
* Refactor `ThreadPool`
* Implement fiber switch events for `TracePoint`
* Add optional tag parameter to #spin
* Correctly increment ref count for indefinite sleep
* Add `irb` adapter
* Add support for listen/notify to postgres adapter
* Use `:waiting`, `:runnable`, `:running`, `:dead` for fiber states
* Move docs to https://digital-fabric.github.io/polyphony/

## 0.27 2020-01-19

* Reimplement `Throttler` using recurring timer
* Add `Gyro::Selector` for wrapping libev
* Add `Gyro::Queue`, a fiber-aware thread-safe queue
* Implement multithreaded fiber scheduling

## 0.26 2020-01-12

* Optimize `IO#read_watcher`, `IO#write_watcher`
* Implement `Fiber#raise`
* Fix `Kernel#gets` with `ARGV`
* Return `[pid, exit_status]` from `Gyro::Child#await`

## 0.25 2020-01-10

* Fold `Coprocess` functionality into `Fiber`
* Add support for indefinite `#sleep`

## 0.24 2020-01-08

* Extract HTTP code into separate polyphony-http gem
* Cull core, io examples
* Remove `SIGINT` handler

## 0.23 2020-01-07

* Remove `API#pulse`
* Better repeat timer, reimplement `API#every`
* Move global API methods to separate module, include in `Object` instead of
  `Kernel`
* Improve setting root fiber and corresponding coprocess
* Fix `ResourcePool#preheat!`
* Rename `$Coprocess#list` to `Coprocess#map`
* Fix `CancelScope#on_cancel`, remove `CancelScope#protect`
* Remove `auto_run` mechanism. Just use `suspend`!
* Optional coverage report for tests
* More tests
* Add `Coprocess.select` and `Supervisor#select` methods
* Add `Coprocess.join` alias to `Coprocess.await` method
* Add support for cancelling multiple coprocesses with a single cancel scope
* Fix stopping a coprocess before it being scheduled for the first time
* Rewrite `thread`, `thread_pool` modules
* Add `Kernel#orig_sleep` alias to sync `#sleep` method
* Add optional resume value to `Gyro::Async#signal!`
* Patch Fiber#inspect to show correct block location
* Add Gyro.run
* Move away from callback-based API for `Gyro::Timer`, `Gyro::Signal`

## 0.22 2020-01-02

* Redesign Gyro scheduling subsystem, go scheduler-less
* More docs
* Rewrite HTTP client agent c1b63787
* Increment Gyro refcount in ResourcePool#acquire
* Rewrite ResourcePool
* Fix socket extensions
* Fix ALPN setup in Net.secure_socket

## 0.21 2019-12-12

* Add Coprocess.await (for waiting for multiple coprocesses)
* Add Coprocess#caller, Coprocess#location methods
* Remove callback-oriented Gyro APIs
* Revise signal handling API
* Improve error handling in HTTP/2 adapter
* More documentation

## 0.20 2019-11-27

* Refactor and improve CancelScope, ResourcePool
* Reimplement cancel_after, move_on_after using plain timers
* Use Timer#await instead of Timer#start in Pulser
* Rename Fiber.main to Fiber.root
* Replace use of defer with proper fiber scheduling
* Improve Coprocess resume, interrupt, cancel methods
* Cleanup code using Rubocop
* Update and cleanup examples
* Remove fiber pool
* Rename `CoprocessInterrupt` to `Interrupt`
* Fix ResourcePool, Mutex, Thread, ThreadPool
* Fix coprocess message passing behaviour
* Add HTTP::Request#consume API
* Use bundler 2.x
* Remove separate parse loop fiber in HTTP 1, HTTP 2 adapters
* Fix handling of exceptions in coprocesses
* Implement synthetic, sanitized exception backtrace showing control flow across
  fibers
* Fix channels
* Fix HTTP1 connection shutdown and error states
* Workaround for IO#read without length
* Rename `next_tick` to `defer`
* Fix race condition in firing of deferred items, use linked list instead of
  array for deferred items
* Rename `EV` module to `Gyro`
* Keep track of main fiber when forking
* Add `<<` alias for `send_chunk` in HTTP::Request
* Implement Socket#accept in C
* Better conformance of rack adapter to rack spec (WIP)
* Fix HTTP1 adapter
* Better support for debugging with ruby-debug-ide (WIP)

## 0.19 2019-06-12

* Rewrite HTTP server for better concurrency, sequential API
* Support 204 no-content response in HTTP 1
* Add optional count parameter to Kernel#throttled_loop for finite looping
* Implement Fiber#safe_transfer in C
* Optimize Kernel#next_tick implementation using ev_idle instead of ev_timer

## 0.18 2019-06-08

* Rename Kernel#coproc to Kernel#spin
* Rewrite Supervisor#spin

## 0.17 2019-05-24

* Implement IO#read_watcher, IO#write_watcher in C for better performance
* Implement nonblocking (yielding) versions of Kernel#system, IO.popen,
  Process.detach, IO#gets IO#puts, other IO singleton methods
* Add Coprocess#join as alias to Coprocess#await
* Rename Kernel#spawn to Kernel#coproc
* Fix encoding of strings read with IO#read, IO#readpartial
* Fix non-blocking behaviour of IO#read, IO#readpartial, IO#write

## 0.16 2019-05-22

* Reorganize and refactor code
* Allow opening secure socket without OpenSSL context

## 0.15 2019-05-20

* Optimize `#next_tick` callback (about 6% faster than before)
* Fix IO#<< to return self
* Refactor HTTP code and examples
* Fix race condition in `Supervisor#stop!`
* Add `Kernel#snooze` method (`EV.snooze` will be deprecated eventually)

## 0.14 2019-05-17

* Use chunked encoding in HTTP 1 response
* Rewrite `IO#read`, `#readpartial`, `#write` in C (about 30% performance improvement)
* Add method delegation to `ResourcePool`
* Optimize PG::Connection#async_exec
* Fix `Coprocess#cancel!`
* Preliminary support for websocket (see `examples/io/http_ws_server.rb`)
* Rename `Coroutine` to `Coprocess`

## 0.13 2019-01-05

* Rename Rubato to Polyphony (I know, this is getting silly...)

## 0.12 2019-01-01

* Add Coroutine#resume
* Improve startup time
* Accept rate: or interval: arguments for throttle
* Set correct backtrace for errors
* Improve handling of uncaught raised errors
* Implement HTTP 1.1/2 client agent with connection management

## 0.11 2018-12-27

* Move reactor loop to secondary fiber, allow blocking operations on main
  fiber.
* Example implementation of erlang-style generic server pattern (implement async
  API to a coroutine)
* Implement coroutine mailboxes, Coroutine#<<, Coroutine#receive, Kernel.receive
  for message passing
* Add Coroutine.current for getting current coroutine

## 0.10 2018-11-20

* Rewrite Rubato core for simpler code and better performance
* Implement EV.snooze (sleep until next tick)
* Coroutine encapsulates a task spawned on a separate fiber
* Supervisor supervises multiple coroutines
* CancelScope used to cancel an ongoing task (usually with a timeout)
* Rate throttling
* Implement async SSL server

## 0.9 2018-11-14

* Rename Nuclear to Rubato

## 0.8 2018-10-04

* Replace nio4r with in-house extension based on libev, with better API,
  better performance, support for IO, timer, signal and async watchers
* Fix mem leak coming from nio4r (probably related to code in Selector#select)

## 0.7 2018-09-13

* Implement resource pool
* transaction method for pg cient
* Async connect for pg client
* Add testing module for testing async code
* Improve HTTP server performance
* Proper promise chaining

## 0.6 2018-09-11

* Add http, redis, pg dependencies
* Move ALPN code inside net module

## 0.4 2018-09-10

* Code refactored and reogranized
* Fix recursion in next_tick
* HTTP 2 server with support for ALPN protocol negotiation and HTTP upgrade
* OpenSSL server

## 0.3 2018-09-06

* Event reactor
* Timers
* Promises
* async/await syntax for promises
* IO and read/write stream
* TCP server/client
* Promised threads
* HTTP server
* Redis interface
* PostgreSQL interface