# frozen_string_literal: true

export_default :SiteConnectionManager

ResourcePool = import '../../core/resource_pool'
HTTP1Adapter = import './http1'

# HTTP site connection pool
class SiteConnectionManager < ResourcePool
  def initialize(uri_key)
    @uri_key = uri_key
    super(limit: 4)
  end

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
      suspend
    when :first_connection
      @first_connection_queue << Fiber.current
      suspend
    end
  end

  def create_first_connection
    @first_connection_queue = []
    @first_connection_queue << Fiber.current

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
    @allocator = make_http2_allocator
  end

  def dequeue_first_connection_waiters
    return unless @first_connection_queue

    @first_connection_queue.each(&:schedule)
    @first_connection_queue = nil
  end

  SECURE_OPTS = { secure: true, alpn_protocols: ['http/1.1'] }.freeze

  def connect
    HTTP1Adapter.new(create_socket)
  end

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

  def http2?
    @http2
  end
end
