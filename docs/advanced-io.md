# @title Advanced I/O with Polyphony

# Advanced I/O with Polyphony

## Using splice for moving data between files and sockets

Splice is linux-specific API that lets you move data between two file
descriptors without copying data between kernel-space and user-space. This is
not only useful for copying data between two files, but also for implementing
things such as web servers, where you might need to serve files of an arbitrary
size. Using splice, you can avoid the cost of having to load a file's content
into memory, in order to send it to a TCP connection.

In order to use `splice`, at least one of the file descriptors involved needs to
be a pipe. This is because in Linux, pipes are actually kernel buffers. The idea
is that you first move data from a source fd into a kernel buffer, then you move
data from the kernel buffer to the destination fd. In some cases, this lets the
Linux kernel completely avoid having to copy data in order to move it from the
source to the destination. So the normal way of using splice is that first you
splice data from the source fd to the pipe (to its *write* fd), and then you
splice data from the pipe (from its *read* fd) to the destination fd.

Here's how you can use splice with Polyphony:

```ruby
def send_file_using_splice(src, dest)
  # create a pipe. Polyphony::Pipe encapsulates a kernel pipe in a single
  # IO-like object, but we can also use the stock IO.pipe method call that
  # returns two separate pipe fds.
  pipe = Polyphony::Pipe.new
  loop do
    # splices data from src to the pipe
    bytes_available = IO.splice(src, pipe, 2**14)
    break if bytes_available == 0 # EOF

    # splices data from the pipe to the dest
    while (bytes_avilable > 0)
      written = IO.splice(pipe, dest, bytes_avilable)
      bytes_avilable -= written
    end
  end
end
```

Let's examine the code above. First of all, we have a loop that repeatedly
splices data in chunks of 16KB, using the `IO.splice` API provided by Polyphony.
We break from the loop once EOF is encountered. Secondly, for moving data from
the pipe to the destination, we need to make sure *all* data made avilable on
the pipe has been spliced to the destination, since the call to `IO.splice` can
actually write fewer bytes than specified. So, we need to repeatedly perform two
splice operations, one after the other, and we need to make sure all data is
spliced to the destination. Would there be a better way to do this?

Fortunately, with Polyphony there is! Firstly, we can tell Polyphony to splice
data repeatedly until EOF is encountered by passing a negative max size:

```ruby
IO.splice(src, pipe, -2**14)
```

Secondly, we can perform the two splice operations concurrently, by spinning up
a separate fiber that performs one of the splice operations, which gives us the
following:

```ruby
def send_file_using_splice(src, dest)
  pipe = Polyphony::Pipe.new
  spin do
    IO.splice(src, pipe, -2**14)
    # We need to close the pipe in order to signal EOF for the 2nd splice call.
    pipe.close
  end
  IO.splice(pipe, dest, -2**14)
end
```

There are a few things to notice here: While we have two concurrent operations
running in two separate fibers, they are still inter-dependent in their
progress, as one is filling a kernel buffer, and the other is flushing it, and
thus the progress of the whole will be bound by the slowest operation.

Take an HTTP server that serves a large file to a slow client, or a client with
a bad network connection. The web server is perfectly capable of reading the
file from its disk very fast, but sending data to the HTTP client can be much
much slower. The second splice operation, splicing from the pipe to the
destination, will flush the kernel buffer much more slowly that it is being
filled. At a certain point, the buffer is full, and the first splice operation
from the source to the pipe cannot continue. It will need to wait for the other
splice operation to progress, in order to continue filling the buffer. This is
called back-pressure propagation, it's a good thing, and we get it
automatically.

Let's now look at all the things we didn't need to do: we didn't need to read
data into a Ruby string (which is costly in CPU time, in memory, and eventually
in GC pressure), we didn't need to manage a buffer and take care of
synchronizing access to the buffer. We got to move data from the source to the
destination concurrently, and we got back-pressure propagation for free. Can we
do any better than that?

Actually, we can! Polyphony also provides an API that does all of the above in a
single method call:

```ruby
def send_file_using_splice(src, dest)
  IO.double_splice(src, dest)
end
```

The `IO.double_splice` creates a pipe and repeatedly splices data concurrently
from the source to the pipe and from the pipe to the destination until the
source is exhausted. All this, without needing to instantiate a
`Polyphony::Pipe` object, and without needing to spin up a second fiber, further
minimizing memory use and GC pressure.

## Compressing and decompressing in-flight data

You might be familiar with Ruby's [zlib](https://github.com/ruby/zlib) gem (docs
[here](https://rubyapi.org/3.2/o/zlib)), which can be used to compress and
uncompress data using the popular gzip format. Imagine we want to implement an
HTTP server that can serve files compressed using gzip:

```ruby
def serve_compressed_file(socket, file)
  # we leave aside sending the HTTP headers and dealing with transfer encoding
  compressed = Zlib.gzip(file.read)
  socket << compressed
end
```

In the above example, we read the file contents into a Ruby string, then pass
the contents to `Zlib.gzip`, which returns the compressed contents in another
Ruby string, then write the compressed data to the socket. We can see how this
can lead to lots of memory allocations (especially if the file is large), and
more pressure on the Ruby GC. How can we improve this?

One way would be to utilise Zlib's `GzipWriter` class:

```ruby
def serve_compressed_file(socket, file)
  # we leave aside sending the HTTP headers and dealing with transfer encoding
  compressor = Zlib::GzipWriter.new(socket)
  while (data = file.read(2**14))
    compressor << data
  end
end
```

In the above code, we instantiate a `Zlib::GzipWriter`, which we then feed with
data from the file, with the compressor object writing the compressed data to
the socket. Notice how we still need to read the file contents into a Ruby
string and then pass it to the compressor. Could we avoid this? With Polyphony
the answer is yes we can!

Polyphony provides a number of APIs for compressing and decompressing data on
the fly between two file descriptors (i.e. `IO` instances), namely: `IO.gzip`,
`IO.gunzip`, `IO.deflate` and `IO.inflate`. Let's see how this can be used to
serve gzipped data to an HTTP client:

```ruby
def serve_compressed_file(socket, file)
  IO.gzip(file, socket) # and that's it!
end
```

Using the `IO.gzip` API provided by Polyphony, we completely avoid instantiating
Ruby strings into which data is read, and in fact we avoid allocating any
buffers on the heap (apart from what `zlib` might be doing). *And* we get to
move data *and compress it* between the given file and the socket using a single
method call!

## Feeding data from a file descriptor to a parser

Some times we want to process data from a given file or socket by passing
through some object that parses the data, or otherwise manipulates it. Normally,
we would write a loop that repeatedly reads the data from the source, then
passes it to the parser object. Imagine we have data transmitted using the
`MessagePack` format that we need to convert back into its original form. We
might do something like the folowing:

```ruby
def with_message_pack_data_from_io(io, &block)
  unpacker = MessagePack::Unpacker.new
  while (data = io.read(2**14))
    unpacker.feed_each(data, &block)
  end
end

# Which we can use as follows:
with_message_pack_data_from_io(socket) do |o|
  puts "got: #{o.inspect}"
end
```

Polyphony provides some APIs that help us write less code, and even optimize the
performance of our code. Let's look at the `IO#read_loop` (or `IO#recv_loop` for
sockets) API:

```ruby
def with_message_pack_data_from_io(io, &block)
  unpacker = MessagePack::Unpacker.new
  io.read_loop do |data|
    unpacker.feed_each(data, &block)
  end
end
```

In the above code, we replaced our `while` loop with a call to `IO#read_loop`,
which yields read data to the block given to it. In the block, we pass the data
to the MessagePack unpacker. While this does not like much different than the
previous implementation, the `IO#read_loop` API implements a tight loop at the
C-extension level, that provides slightly better performance.

But Polyphony goes even further than that and provides a `IO#feed_loop` API that
lets us feed read data to a given parser or processor object. Here's how we can
use it:

```ruby
def with_message_pack_data_from_io(io, &block)
  unpacker = MessagePack::Unpacker.new
  io.feed_loop(unpacker, :feed_each, &block)
end
```

With `IO#feed_loop` we get to write even less code, and as with `IO#read_loop`,
`IO#feed_loop` is implemented at the C-extension level using a tight loop that
maximizes performance.

## Fast and easy chunked transfer-encoding in HTTP/1

[Chunked transfer
encoding](https://en.wikipedia.org/wiki/Chunked_transfer_encoding) is a great
way to serve HTTP responses of arbitrary size, because we don't need to know
their size in advance, which means we don't necessarily need to hold them in
memory, or perform expensive fstat calls to get file metadata. Sending HTTP
responses in chunked transfer encoding is simple enough:

```ruby
def send_chunked_response_from_io(socket, io)
  while true
    chunk = io.read(MAX_CHUNK_SIZE)
    socket << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
    break if chunk.empty?
  end
end
```

Note how we read the chunk into memory and then send it on to the client. Would
it be possible to splice the data instead? Let's see how that would look:

```ruby
def send_chunked_response_from_io(socket, io)
  pipe = Polyphony::Pipe.new
  while true
    bytes_spliced = IO.splice(io, pipe, MAX_CHUNK_SIZE)
    socket << "#{bytes_spliced.to_s(16)}\r\n"
    IO.splice(pipe, socket, bytes_spliced) if bytes_spliced > 0
    socket << "\r\n"
    break if bytes_spliced == 0
  end
end
```

In the code above, while we avoid having to read chunks of the source data into
Ruby strings, we now perform 3 I/O operations for each chunk: writing the chunk
size, splicing the data from the pipe (the kernel buffer), and finally writing
the `"\r\n"` delimiter. We can probably write some more complex logic to reduce
this to 2 operations (coalescing the two write operations into one), but still
this implementation involves a lot of back and forth between our code, the
Polyphony I/O backend, and the operating system.

Fortunately, Polyphony provides a special API for sending HTTP chunked
responses:

```ruby
def send_chunked_response_from_io(socket, io)
  IO.http1_splice_chunked(io, socket, MAX_CHUNK_SIZE)
end
```

A single method call replaces the whole mechanism we devised above, and in
addition Polyphony makes sure to perform it with the minimum possible number of
I/O operations!

# Sending compressed data using chunked transfer encoding

We can now combine the different APIs discussed above to create even more
complex behaviour. Let's see how we can send an HTTP response using compressed
content encoding and chunked transfer encoding:

```ruby
def send_compressed_chunked_response_from_io(socket, io)
  pipe = Polyphony::Pipe.new
  spin { IO.gzip(io, pipe) }
  IO.http1_splice_chunked(pipe, socket, MAX_CHUNK_SIZE)
end
```

The code above looks simple enough, but it actually packs a lot of power in just
3 lines of code: we create a pipe, then spin up a fiber that compresses data
data `io` into the pipe. We then serve data from the pipe to the socket using
chunked transfer encoding. As discussed above, we do this without actually
allocating any Ruby strings for holding the data, we take maximum advantage of
kernel buffers (a.k.a. pipes) and we perform the two operations - compressing
the data and sending it to the client - concurrently.

## Conclusion

In this article we have looked at some of the advanced I/O functionality
provided by Polyphony, which lets us write less code, have it run faster, have
it run concurrently, and minimize memory allocations and pressure on the Ruby
GC. Feel free to browse the [IO
examples](https://github.com/digital-fabric/polyphony/tree/master/examples/io)
included in Polyphony.