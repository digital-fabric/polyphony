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