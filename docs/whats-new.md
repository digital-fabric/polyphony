# @title What's New?

# What's New in 0.44?

## More performance, more compatibility, more robustness

The last three weeks have been very busy for Polyphony. Since I first presented
Polyphony here and elsewhere, 17 issues were closed, 10 pull requests were
merged, and 144 commits were made by 4 different authors. I'm really
excited about Polyphony and the momentum it seems to be gathering. Your
reactions have been very positive so far (it even got [tweeted by
Matz!](https://twitter.com/yukihiro_matz/status/1279289318083715073))

I'm even more excited about the contributions Polyphony is starting to get from
other developers. Thank you [Will](https://github.com/wjordan),
[Máximo](https://github.com/ElMassimo) and [Trent](https://github.com/misfo) for
your valuable contributions! Also, the Polyphony project has now got a logo
designed by my friend [Gérald Morales](https://webocube.com/).

I'd like to encourage other developers to get in on the action and start
contributing by testing Polyphony, creating issues and writing code and
documentation. Together we can make Polyphony a game-changer for developing
concurrent apps in Ruby, and finally put to rest the notion that "Ruby is slow"!

Since the last public release of Polyphony, we have focused on fixing bugs,
improving performance and introducing new features that improve the Polyphony
developer experience. Polyphony 0.44 is up to 20% percent faster than the
previous release, due notably to a new ring-buffer implementation used by the
fiber run queue and the `Polyphony::Queue` class, a new `Backend#read_loop` API
for tighter server loops, and minimizing `fcntl` syscalls when doing I/O. These
and other minor improvements have resulted in Polyphony first crossing the
50,000 requests per second threshold for the first time in a minimal [rack
server
example](https://github.com/digital-fabric/polyphony/blob/master/examples/io/xx-rack_server.rb).

Notable new features include a MySQL adapter, a Sequel adapter, and a new
`Fiber#interject` API that allows executing arbitrary code on arbitrary fibers.

We have also fixed numerous bugs, among which an issue building Polyphony on
MacOS, problems issuing `Net::HTTP` requests with secure URLs, an issue with
`YAML.load` and much more...

For the full list of changes please consult the [change log](https://github.com/digital-fabric/polyphony/blob/master/CHANGELOG.md).

## What's next for Polyphony?

The next release of Polyphony will focus on full support IRB and Pry. Being able
to run operations in the background in IRB and Pry can be very beneficial, most
of all when developing and when debugging running processes using `binding.pry`
for example.

Subsequent releases will introduce a whole new full-featured debugger for
fiber-aware concurrent apps, and eventually full support for Sequel, Sinatra,
Hanami, Sidekiq and other major areas of the Ruby ecosystem.

## Tipi - a polyphonic web server for Ruby

[Tipi](https://github.com/digital-fabric/tipi) is a new web server for Ruby
apps. It is intended to be *the* go-to app server for Ruby apps looking for
robustness, scalability and performance. Tipi already supports HTTP/1, HTTP/2,
WebSockets and SSL termination. It can currently drive simple Rack apps. In the
future Tipi will be fully compliant with the Rack specification, and will also
offer a static file server, a rich configuration  and automatic TLS certificates
(using Let's Encrypt) out of the box.

For those wondering about performance, here are some preliminary numbers (see
disclaimer below):

- HTTP, hello world, single process: ~50000 requests/second
- HTTP, Rack hello world app, single process: ~33000 requests/second
- HTTP, Rack hello world, 4 worker processes: ~95000 requests/second
- HTTPS, hello world, single process: ~20000 requests/second
- HTTPS, hello world, 4 worker processes: ~72000 requests/second

Disclaimer: these numbers should be taken with a grain of salt. They do not
follow any established benchmarking methodology, and may vary significantly. The
different configurtations were benchmarked using the command: `wrk -d10 -t1 -c10
"<http|https>://127.0.0.1:1234/"` on the same machine (an `m2.xlarge` instance)
as the server. In the future Tipi's performance might substantially change. YMMV.