# Roadmap:

## 0.20 REPL usage, coprocess introspection, monitoring

- Implement `move_on_after(1, with: nil) { ... }`
- Implement `Coprocess.await` for waiting on multiple coprocesses without
  starting them in a supervisor, will also necessitate adding `Supervisor#add`
- Implement `Coprocess#location`
- Implement `Coprocess#alive?`
- Implement `Coprocess#caller` - points to coprocess that called the coprocess
- Implement `Coprocess.list` - a list of running coprocesses

## 0.21 Full Rack adapter implementation

- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?
- Rewrite agent code to use sequential API (like I did for server)
- Streaming bodies for HTTP client

  ```ruby
  def download_doc
    response = Polyphony::HTTP::Agent.get('https://acme.com/doc.pdf')
    File.open('doc.pdf', 'wb+') do |f|
      response.each { |chunk| f << chunk } # streaming body
    end
  end
  ```

- find some demo Rack apps and test with Polyphony

## 0.22 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.23 Support for multi-threading

- Separate event loop for each thread

## 0.24 Testing

- test thread / thread_pool modules
- report test coverage

## 0.25 Documentation

# DNS

## DNS client

```ruby
ip_address = DNS.lookup('google.com', 'A')
```

Prior art:

- https://github.com/alexdalitz/dnsruby
- https://github.com/eventmachine/eventmachine/blob/master/lib/em/resolver.rb
- https://github.com/gmodarelli/em-resolv-replace/blob/master/lib/em-dns-resolver.rb
- https://github.com/socketry/async-dns

### DNS server

```ruby
Server = import('../../lib/polyphony/dns/server')

server = Server.new do |transaction|
  puts "got query from #{transaction.info[:client_ip_address]}"
  transaction.questions.each do |q|
    respond(transaction, q[:domain], q[:resource_class])
  end
end

server.listen(port: 5300)
puts "listening on port 5300"
```

Prior art:

- https://github.com/socketry/async-dns

