# frozen_string_literal: true

pid = Process.pid
fork do
  sleep 1
  Process.kill('SIGINT', pid)
  # sleep 10
  # Process.kill(-9, pid)
end

trap('SIGINT') {}
p :before
result = IO.select([STDIN])
p :after