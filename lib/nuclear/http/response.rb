# frozen_string_literal: true

export_default :Response

# HTTP 1.1 Response
class Response
  attr_reader :socket, :headers_sent
  attr_accessor :status_code

  # Initializes response
  # @param socket [Socket]
  # @param &on_finished [Proc] callback called once response is finished
  def initialize(socket, &on_finished)
    @socket = socket
    @on_finished = on_finished
    reset!
  end

  # Returns nil as the protocol used
  # @return [nil]
  def protocol
    nil
  end

  # Resets response so it can be reused
  # @return [void]
  def reset!
    @status_code = 200
    @headers ? @headers.clear : (@headers = +'')
    @headers_sent = nil
  end

  # Sets response header
  # @param key [Symbol, String] header key
  # @param value [any] header value
  # @return [void]
  def set_header(key, value)
    @headers << "#{key}: #{value}\r\n"
  end

  # Sets the status code and response headers. The response headers will not
  # actually be sent until #send_headers is called.
  # @param status_code [Integer] HTTP status code
  # @param headers [Hash] response headers
  # @return [void]
  def write_head(status_code = 200, headers = {})
    raise 'Headers already sent' if @headers_sent

    @status_code = status_code
    headers.each do |k, v|
      if v.is_a?(Array)
        v.each { |vv| @headers << "#{k}: #{vv}\r\n" }
      else
        @headers << "#{k}: #{v}\r\n"
      end
    end
  end

  # Writes response body to connection
  # @param data [String] response body
  # @param finish [Boolean] whether to finish response
  # @return [void]
  def write(data, finish = nil)
    if @headers_sent
      send(data, finish)
    else
      set_header('Content-Length', data.bytesize) if data && finish
      send_headers_and_body(data, finish)
    end
  end

  # Finish response, optionally writing response body
  # @param data [String, nil] response body
  # @return [void]
  def finish(data = nil)
    write(data, true)
    @on_finished&.()
  end

  private

  # Sends response body, optionally finishing the response
  # @param data [String] response body
  # @param _finish [Boolean] whether the response is finished
  # @return [void]
  def send(data, _finish)
    @socket << data if data
  end

  # Sends status code and headers
  # @return [void]
  def send_headers
    @socket << "HTTP/1.1 #{@status_code}\r\n#{@headers}\r\n"
    @headers_sent = true
  end

  def send_headers_and_body(data, _finish)
    @socket << "HTTP/1.1 #{@status_code}\r\n#{@headers}\r\n#{data}"
    @headers_sent = true
  end
end
