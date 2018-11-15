# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

class IO
  async def read_some(max = 8192)
    Rubato::Task.new do |t|
      read_from_io(t, max)
    end
  end

  NO_EXCEPTION_OPTS = { exception: false }.freeze

  def read_from_io(task, max)
    buffer = +''
    result = read_nonblock(max, buffer, NO_EXCEPTION_OPTS)
    case result
    when nil
      task.resolve RuntimeError.new('socket closed')
    when :wait_readable
      fiber = Fiber.current
      create_read_watcher unless @read_watcher
      @read_watcher.start do
        @read_watcher.stop
        task.resolve read_nonblock(max, buffer, NO_EXCEPTION_OPTS)
      end
      task.on_cancel { @read_watcher.stop }
    else
      task.resolve buffer
    end
  rescue => e
    STDOUT.puts "error: #{e}"
    STDOUT.puts e.backtrace.join("\n")
    task.resolve(e)
  end

  def create_read_watcher
    @read_watcher = EV::IO.new(self, :r, true) {}
  end
end

spawn do
  stdin = Rubato::IOWrapper.new(STDIN)
  puts "Write something..."
  cancel_after(10) do |scope|
    loop do
      data = await stdin.read
      scope.reset_timeout
      puts "you wrote: #{buffer}"
    end
  end
rescue Cancelled
  puts "quitting due to inactivity"
end
