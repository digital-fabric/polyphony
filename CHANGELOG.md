0.28 2020-01-27
---------------

* Accept block in Supervisor#initialize
* Refactor `ThreadPool`
* Implement fiber switch events for `TracePoint`
* Add optional tag parameter to #spin
* Correctly increment ref count for indefinite sleep
* Add `irb` adapter
* Add support for listen/notify to postgres adapter
* Use `:waiting`, `:runnable`, `:running`, `:dead` for fiber states
* Move docs to https://digital-fabric.github.io/polyphony/

0.27 2020-01-19
---------------

* Reimplement `Throttler` using recurring timer
* Add `Gyro::Selector` for wrapping libev
* Add `Gyro::Queue`, a fiber-aware thread-safe queue
* Implement multithreaded fiber scheduling

0.26 2020-01-12
---------------

* Optimize `IO#read_watcher`, `IO#write_watcher`
* Implement `Fiber#raise`
* Fix `Kernel#gets` with `ARGV`
* Return `[pid, exit_status]` from `Gyro::Child#await`

0.25 2020-01-10
---------------

* Fold `Coprocess` functionality into `Fiber`
* Add support for indefinite `#sleep`

0.24 2020-01-08
---------------

* Extract HTTP code into separate polyphony-http gem
* Cull core, io examples
* Remove `SIGINT` handler

0.23 2020-01-07
---------------

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

0.22 2020-01-02
---------------

* Redesign Gyro scheduling subsystem, go scheduler-less
* More docs
* Rewrite HTTP client agent c1b63787
* Increment Gyro refcount in ResourcePool#acquire
* Rewrite ResourcePool
* Fix socket extensions
* Fix ALPN setup in Net.secure_socket

0.21 2019-12-12
---------------

* Add Coprocess.await (for waiting for multiple coprocesses)
* Add Coprocess#caller, Coprocess#location methods
* Remove callback-oriented Gyro APIs
* Revise signal handling API
* Improve error handling in HTTP/2 adapter
* More documentation

0.20 2019-11-27
---------------

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

0.19 2019-06-12
---------------

* Rewrite HTTP server for better concurrency, sequential API
* Support 204 no-content response in HTTP 1
* Add optional count parameter to Kernel#throttled_loop for finite looping
* Implement Fiber#safe_transfer in C
* Optimize Kernel#next_tick implementation using ev_idle instead of ev_timer

0.18 2019-06-08
---------------

* Rename Kernel#coproc to Kernel#spin
* Rewrite Supervisor#spin

0.17 2019-05-24
---------------

* Implement IO#read_watcher, IO#write_watcher in C for better performance
* Implement nonblocking (yielding) versions of Kernel#system, IO.popen,
  Process.detach, IO#gets IO#puts, other IO singleton methods
* Add Coprocess#join as alias to Coprocess#await
* Rename Kernel#spawn to Kernel#coproc
* Fix encoding of strings read with IO#read, IO#readpartial
* Fix non-blocking behaviour of IO#read, IO#readpartial, IO#write

0.16 2019-05-22
---------------

* Reorganize and refactor code
* Allow opening secure socket without OpenSSL context

0.15 2019-05-20
---------------

* Optimize `#next_tick` callback (about 6% faster than before)
* Fix IO#<< to return self
* Refactor HTTP code and examples
* Fix race condition in `Supervisor#stop!`
* Add `Kernel#snooze` method (`EV.snooze` will be deprecated eventually)

0.14 2019-05-17
---------------

* Use chunked encoding in HTTP 1 response
* Rewrite `IO#read`, `#readpartial`, `#write` in C (about 30% performance improvement)
* Add method delegation to `ResourcePool`
* Optimize PG::Connection#async_exec
* Fix `Coprocess#cancel!`
* Preliminary support for websocket (see `examples/io/http_ws_server.rb`)
* Rename `Coroutine` to `Coprocess`

0.13 2019-01-05
---------------

* Rename Rubato to Polyphony (I know, this is getting silly...)

0.12 2019-01-01
---------------

* Add Coroutine#resume
* Improve startup time
* Accept rate: or interval: arguments for throttle
* Set correct backtrace for errors
* Improve handling of uncaught raised errors
* Implement HTTP 1.1/2 client agent with connection management

0.11 2018-12-27
---------------

* Move reactor loop to secondary fiber, allow blocking operations on main
  fiber.
* Example implementation of erlang-style generic server pattern (implement async
  API to a coroutine)
* Implement coroutine mailboxes, Coroutine#<<, Coroutine#receive, Kernel.receive
  for message passing
* Add Coroutine.current for getting current coroutine

0.10 2018-11-20
---------------

* Rewrite Rubato core for simpler code and better performance
* Implement EV.snooze (sleep until next tick)
* Coroutine encapsulates a task spawned on a separate fiber
* Supervisor supervises multiple coroutines
* CancelScope used to cancel an ongoing task (usually with a timeout)
* Rate throttling
* Implement async SSL server

0.9 2018-11-14
--------------

* Rename Nuclear to Rubato

0.8 2018-10-04
--------------

* Replace nio4r with in-house extension based on libev, with better API,
  better performance, support for IO, timer, signal and async watchers
* Fix mem leak coming from nio4r (probably related to code in Selector#select)

0.7 2018-09-13
--------------

* Implement resource pool
* transaction method for pg cient
* Async connect for pg client
* Add testing module for testing async code
* Improve HTTP server performance
* Proper promise chaining

0.6 2018-09-11
--------------

* Add http, redis, pg dependencies
* Move ALPN code inside net module

0.4 2018-09-10
--------------

* Code refactored and reogranized
* Fix recursion in next_tick
* HTTP 2 server with support for ALPN protocol negotiation and HTTP upgrade
* OpenSSL server

0.3 2018-09-06
--------------

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