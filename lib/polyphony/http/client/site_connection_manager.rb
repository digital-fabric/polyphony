# frozen_string_literal: true

export_default :SiteConnectionManager

ResourcePool = import '../../core/resource_pool'
HTTP1Adapter = import './http1'
HTTP2Adapter = import './http2'

# HTTP site connection pool
class SiteConnectionManager < ResourcePool
  def initialize(uri_key)
    @uri_key = uri_key
    super(limit: 4)
  end

  # def method_missing(sym, *args)
  #   raise "Invalid method #{sym}"
  # end

  def acquire
    Gyro.ref
    prepare_first_connection if @size.zero?
    super
  ensure
    Gyro.unref
    # The size goes back to 0 only in case existing connections get into an
    # error state and then get discarded
    @state = nil if @size == 0
  end

  def prepare_first_connection
    case @state
    when nil
      @state = :first_connection
      create_first_connection
    when :first_connection
      @first_connection_queue << Fiber.current
      suspend
    end
  end

  def create_first_connection
    @first_connection_queue = []
    # @first_connection_queue << Fiber.current

    adapter = connect
    @state = adapter.protocol
    send(:"setup_#{@state}_allocator", adapter)
    dequeue_first_connection_waiters
  end

  def setup_http1_allocator(adapter)
    @size += 1
    adapter.extend ResourceExtensions
    @stock << adapter
    @allocator = proc { connect }
  end

  def setup_http2_allocator(adapter)
    @adapter = adapter
    @limit = 20
    @size += 1
    stream_adapter = adapter.allocate_stream_adapter
    stream_adapter.extend ResourceExtensions
    @stock << stream_adapter
    @allocator = proc { adapter.allocate_stream_adapter }
  end

  def dequeue_first_connection_waiters
    return unless @first_connection_queue

    @first_connection_queue.each(&:schedule)
    @first_connection_queue = nil
  end

  def connect
    socket = create_socket
    protocol = socket_protocol(socket)
    case protocol
    when :http1
      HTTP1Adapter.new(socket)
    when :http2
      HTTP2Adapter.new(socket)
    else
      raise "Unknown protocol #{protocol.inspect}"
    end
  end

  def socket_protocol(socket)
    if socket.is_a?(OpenSSL::SSL::SSLSocket) && socket.alpn_protocol == 'h2'
      :http2
    else
      :http1
    end
  end

  SECURE_OPTS = { secure: true, alpn_protocols: ['h2', 'http/1.1'] }.freeze

  def create_socket
    case @uri_key[:scheme]
    when 'http'
      Polyphony::Net.tcp_connect(@uri_key[:host], @uri_key[:port])
    when 'https'
      Polyphony::Net.tcp_connect(@uri_key[:host], @uri_key[:port], SECURE_OPTS)
    else
      raise "Invalid scheme #{@uri_key[:scheme].inspect}"
    end
  end
end
