SERVERS = {
  polyphony: {
    port: 1234,
    cmd: 'ruby examples/performance/thread-vs-fiber/polyphony_server.rb'
  },
  threaded: {
    port: 1235,
    cmd: 'ruby examples/performance/thread-vs-fiber/threaded_server.rb'
  },
  em: {
    port: 1236,
    cmd: 'ruby examples/performance/thread-vs-fiber/em_server.rb'
  }
}
SETTINGS = [
  '-t1 -c1',
  '-t4 -c8',
  '-t8 -c64',
  '-t16 -c512',
  '-t32 -c4096',
  '-t64 -c8192',
  '-t128 -c16384',
  '-t256 -c32768'
]

def run_test(name, port, cmd, setting)
  puts "*" * 80
  puts "Run #{name} (#{port}): #{setting}"
  puts "*" * 80

  pid = spawn("#{cmd} > /dev/null 2>&1")
  sleep 1

  output = `wrk -d60 #{setting} \"http://127.0.0.1:#{port}/\"`
  puts output
  (output =~ /Requests\/sec:\s+(\d+)/) && $1.to_i
ensure
  Process.kill('KILL', pid)
  Process.wait(pid)
  3.times { puts }
end

def perform_benchmark
  results = []
  SETTINGS.each do |s|
    results << SERVERS.inject({}) do |h, (n, o)|
      h[n] = run_test(n, o[:port], o[:cmd], s)
      h
    end
  end
  results
end

results = []
3.times { results << perform_benchmark }

require 'pp'
puts "results:"
pp results
