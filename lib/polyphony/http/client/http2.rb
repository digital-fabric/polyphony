# frozen_string_literal: true

export_default :HTTP2Adapter

require 'http/2'

Response = import './response'

# HTTP 2 adapter
class HTTP2Adapter
  def initialize(socket)
    @socket = socket
    @client = HTTP2::Client.new
    @client.on(:frame) { |bytes| socket << bytes }
    # @client.on(:frame_received) do |frame|
    #   puts "Received frame: #{frame.inspect}"
    # end
    # @client.on(:frame_sent) do |frame|
    #   puts "Sent frame: #{frame.inspect}"
    # end

    @reader = spin do
      while (data = socket.readpartial(8192))
        @client << data
        snooze
      end
    end
  end

  def allocate_stream_adapter
    StreamAdapter.new(self)
  end

  def allocate_stream
    @client.new_stream
  end

  def protocol
    :http2
  end

  # Virtualizes adapter over HTTP2 stream
  class StreamAdapter
    def initialize(connection)
      @connection = connection
    end

    def request(ctx)
      stream = setup_stream # (ctx, stream)
      send_request(ctx, stream)

      stream.on(:headers, &method(:on_headers))
      stream.on(:data, &method(:on_data))
      stream.on(:close, &method(:on_close))

      # stream.on(:active) { puts "* active" }
      # stream.on(:half_close) { puts "* half_close" }

      wait_for_response(ctx, stream)
    rescue Exception => e
      p e
      puts e.backtrace.join("\n")
      # ensure
      # stream.close
    end

    def send_request(ctx, stream)
      headers = prepare_headers(ctx)
      if ctx[:opts][:payload]
        stream.headers(headers, end_stream: false)
        stream.data(ctx[:opts][:payload], end_stream: true)
      else
        stream.headers(headers, end_stream: true)
      end
    end

    def on_headers(headers)
      if @waiting_headers_fiber
        @waiting_headers_fiber.schedule headers.to_h
      else
        @headers = headers.to_h
      end
    end

    def on_data(chunk)
      if @waiting_chunk_fiber
        @waiting_chunk_fiber&.schedule chunk
      else
        @buffered_chunks << chunk
      end
    end

    def on_close(_stream)
      @done = true
      @waiting_done_fiber&.schedule
    end

    def setup_stream
      stream = @connection.allocate_stream

      @headers = nil
      @done = nil
      @buffered_chunks = []

      @waiting_headers_fiber = nil
      @waiting_chunk_fiber = nil
      @waiting_done_fiber = nil

      stream
    end

    def wait_for_response(_ctx, _stream)
      headers = wait_for_headers
      Response.new(self, headers[':status'].to_i, headers)
    end

    def wait_for_headers
      return @headers if @headers

      @waiting_headers_fiber = Fiber.current
      suspend
    end

    def protocol
      :http2
    end

    def prepare_headers(ctx)
      headers = {
        ':method'    => ctx[:method].to_s,
        ':scheme'    => ctx[:uri].scheme,
        ':authority' => [ctx[:uri].host, ctx[:uri].port].join(':'),
        ':path'      => ctx[:uri].request_uri,
        'User-Agent' => 'curl/7.54.0'
      }
      headers.merge!(ctx[:opts][:headers]) if ctx[:opts][:headers]
      headers
    end

    def body
      @waiting_done_fiber = Fiber.current
      suspend
      @buffered_chunks.join
      # body = +''
      # while !@done
      #   p :body_suspend_pre
      #   chunk = suspend
      #   p :body_suspend_post
      #   body << chunk
      # end
      # puts ""
      # body
    rescue Exception => e
      p e
      puts e.backtrace.join("\n")
    end

    def each_chunk
      yield @buffered_chunks.shift until @buffered_chunks.empty?

      @waiting_chunk_fiber = Fiber.current
      until @done
        chunk = suspend
        yield chunk
      end
    end

    def next_body_chunk
      return yield @buffered_chunks.shift unless @buffered_chunks.empty?

      @waiting_chunk_fuber = Fiber.current
      until @done
        chunk = suspend
        return yield chunk
      end

      nil
    end
  end
end
