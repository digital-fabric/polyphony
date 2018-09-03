## Nicer interface for watching i/o:

```ruby
Reactor.watch(socket, :rw) do |readable, writable|
  if readable
    ...
  end
  if writable
    ...
  end
end
```

Or maybe:

```ruby
Reactor.watch(socket,
  read: -> { ... },
  write: -> { ... }
)
```

## Mutex (is this really needed, since we're doing single thread programming?)

```ruby

@mutex = Mutex.new

async do
  ...
  result = await @mutex.synchronize do

  end
  ...
end
```

## Timeouts

Manually:

```ruby
def connect
  Promise.new(timeout: @opts[:timeout]) do |p|
    timeout = Reactor.timeout(@opts[:timeout]) do
      cleanup
      p.error(Timeout)
    end
  end
```

built in with callback:

```ruby
def connect
  Promise.new(timeout: @opts[:timeout]) do |p|
    ...
    p.on_timeout do
      cleanup
    end
  end
end
```

timeout method:

```ruby
def connect
  Promise.new do |p|
    ...
    p.timeout(@opts[:timeout]) do
      cleanup
    end
    ...
  end
end
```






## node-like API with events:

```ruby
TCP = import('nuclear/tcp')

socket = TCP::Socket.new(...)

# events
socket.on(:connect) { ... }
socket.on(:close) { ... }
socket.on(:data) { |data| ... }
socket.on(:drain) { ... }
socket.on(:timeout) { ... }
socket.on(:error) { ... }

# client
socket = TCP.create_connection(port: 8124) do
  # :connect event
  puts 'connected to server!'
  socket.write("hi\r\n")
end

socket.on(:data) do |data|
  puts data
  socket.close
end

socket.on(:end) do
  puts 'disconnected from server'
end

# server

server = TCP.create_server do |c|
  # :connection event
  puts 'client connected'
  c.on(:end) do
    puts 'client disconnected'
  end
  c.write("hello\r\n")
  c.on(:data) do |data|
    c.write(data)
  end
end
server.on(:error) do |err|
  puts err
end

server.listen(8124) do
  # :listening event
  puts 'server bound'
end
```

## Promisifying blocks for methods that take blocks

```ruby
class Server
  def incoming_connection(&block)
    Promise.new(block) do |p|
      ...
    end
  end
end

# callback-style
server.listen do |connect|
  puts 'listening'
end

# promise-style
await server.listen
```

## async blocks

```ruby
# explicit wrap
Reactor.timeout(1) do
  async do
    await socket.write('hello')
  end
end

# or:
Reactor.timeout(1) { async {
  await socket.write('hello')
} }

# use separate method for doing async procs
Reactor.timeout(1, &deferred {
  await socket.write('hello')
})

# Proc#async
Reactor.timeout(1, &-> {
  await socket.write('hello')
}.async)

# use async as proc
Reactor.timeout 1, &async_block(-> {
  await socket.write('hello')
})
```


## queueing

```ruby
# by chaining promises
def write(data)
  raise RuntimeError.new("Not connected") unless connected?

  Concurrency::Promise(chain: @drain_promise).new do |p|
    @drain_promise = p
    @write_buffer << data
    write_to_socket
  end
end

# inline chaining
def write(data)
  raise RuntimeError.new("Not connected") unless connected?

  Concurrency::Promise.new do |p|
    # @drain_promise = p
    # @write_buffer << data
    # write_to_socket
  end
end

# by proper queuing
def write(data)
  promise = Concurrency::Promise(defer: true).new do |p|
    @drain_promise = p
    @write_buffer << data
    write_to_socket
  end

  if @drain_promise
    @write_queue << promise
    @drain_promise.chain(p.action)
  else
    p.action.()
  end
  
  promise
end
```

## Streams

```ruby
# readline generalized
def echo_connection(socket)
  lines = Readline.new(socket)
  while lines.connected?
    text = await(lines.gets) rescue nil
    await(socket.write(text)) if text
  end
end

# Stream as Enumerable / generator
def echo_connection(socket)
  lines = Readline.new(socket)
  lines.each do |line|
    socket.write(line)
  end
end

# Stream can be piped:
def echo_connection(socket)
  lines = Readline.new(socket)
  lines.pipe(socket)
end

# Piping to a parser
def setup_http_connection(socket)
  parser = HTTP::Parser.new
  socket.pipe(parser)
  parser.on_message_complete do
    handle_request(socket, parser)
    if parser.keep_alive?
      parser.reset!
    else
      socket.close
    end
  end
end

# A bit less naïve
def setup_http_connection(socket)
  parser = HTTP::Parser.new

  socket.on(:data) do |data|

  end

  socket.pipe(parser)
  parser.on_message_complete do
    handle_request(socket, parser)
    if parser.keep_alive?
      parser.reset!
    else
      socket.close
    end
  end
end
```

## socket as stream

```ruby
# implementation
class Socket < Stream
  def _write(chunk, encoding, &callback)
    @write_callback = callback
    @write_chunk = chunk
    @write_chunk_pos = 0
    write_to_socket
  end

  def read_from_socket
    ...
    _read(chunk)
  end
end

# API
def echo_connection(socket)
  reader = Readline.new
  socket.pipe(reader)

  while (line = await reader.gets)
    socket << "You said: #{line}"
  end
end

def http_connection(socket)
  parser = HTTP::Parser.new

  socket.on(:data) do |data|
    parser << data
  end
  
  # or:
  socket.pipe(parser)

  parser.on_message_complete do
    handle_request(socket, parser)
    if parser.keep_alive?
      parser.reset!
    else
      socket.close
    end
  end
end
```

## What about handling errors in callbacks?

```ruby
def http_connection(socket)
  parser = HTTP::Parser.new

  socket.on(:data) do |data|
    # since HTTP::Parser is "dum", the following can raise a parsing error
    parser << data
  end

  ...
end

# If HTTP::Parser could understand promises
def http_connection(socket)
  parser = HTTP::Parser.new

  socket.pipe(parser)

  while request = await parser.get_request
    handle_request(socket, request)
  end
rescue => e
  socket.close
end

# Do it manually
def http_connection(socket)
  request_generator(socket).each do |req|
    handle_request(req)
    if req.keep_alive?
      req.reset!
    else
      socket.close
    end
  end
end

def request_generator(socket)
  parser = HTTP::Parser.new

  generator do |g|
    socket.on(:data) do |data|
      pipe_data_to_parser(data, parser, g)
    end
    parser.on_message_complete { g.resolve(parser) }
  end
end

def pipe_data_to_parser(data, parser, generator)
  parser << data
rescue => e
  generator.error(e)
end
```

