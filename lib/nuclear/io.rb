# frozen_string_literal: true

export_default :IO

Stream =      import('./stream')
Concurrency = import('./concurrency')
Reactor =     import('./reactor')
LineReader =  import('./line_reader')

class IO < Stream
  def self.lines(io)
    LineReader.new(io).lines
  end

  def self.stdin
    @stdin ||= new(STDIN)
  end

  def self.stdout
    @stdout ||= new(STDOUT, write_only: true)
  end

  def initialize(io, opts = {})
    super(opts)
    @io = io
    @open = true
    watch_io if io
  end

  def raw_io
    @io
  end

  def watch_io
    update_monitor_interests(:r)
  end

  def create_monitor(interests)
    @monitor = Reactor.watch(@io, interests) do
      case @monitor.readiness
      when :r, :rw
        read_from_io
      when :w, :rw
        write_to_io
      end
    end
  end

  def update_monitor_interests(interests)
    interests = verify_monitor_interests(interests)
    if @monitor
      if interests.nil?
        Reactor.unwatch(@io)
        @monitor = nil
      else
        @monitor.interests = interests
      end
    elsif interests
      create_monitor(interests)
    end
  end

  def verify_monitor_interests(interests)
    return interests unless @opts[:write_only]
    case interests
    when :r
      nil
    when :rw
      :w
    else
      interests
    end
  end

  def <<(data)
    @write_buffer << data
    write_to_io
  end

  def write(data)
    Concurrency.promise do |p|
      @callbacks[:drain] = proc { p.resolve(true) }
      self << data
      @callbacks[:drain] = nil
    end
  end

  READ_MAX_CHUNK_SIZE = 2 ** 20
  NO_EXCEPTION_OPTS = {exception: false}

  def read_from_io
    loop do
      case (data = @io.read_nonblock(READ_MAX_CHUNK_SIZE, NO_EXCEPTION_OPTS))
      when nil
        return connection_was_closed
      when :wait_readable
        return
      else
        @callbacks[:data]&.(data)
      end
    end
  rescue => e
    close_on_error(e)
  end

  def write_to_io
    loop do
      result = @io.write_nonblock(@write_buffer, exception: false)
      case result
      when :wait_writable
        return update_monitor_interests(:rw)
      when nil
        return connection_was_closed
      else
        break unless slice_write_buffer(result)
      end
    end
    @callbacks[:drain]&.()
  rescue => e
    close_on_error(e)
  end

  # Slices write buffer, returns true if more left to write
  def slice_write_buffer(written)
    if written == @write_buffer.bytesize
      update_monitor_interests(:r)
      @write_buffer.clear
      @callbacks[:drain]&.()
      false
    else
      @write_buffer.slice!(0, written)
      true
    end
  end

  def close_on_error(err)
    puts "error: #{err.inspect}"
    puts err.backtrace.join("\n")
    @callbacks[:error]&.(err)
    close
  end

  def connection_was_closed
    close
  end

  def close
    Reactor.unwatch(@io)
    @io.close
    @open = false
    @connected = false
    @read_buffer = nil
    @write_buffer = nil
    @io = nil
    @callbacks[:close]&.()
  rescue => e
    puts "error while closing: #{e}"
  end
end

