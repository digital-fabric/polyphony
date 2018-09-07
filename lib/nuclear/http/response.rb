# frozen_string_literal: true

export_default :Response

# HTTP 1.1 Response
class Response
  attr_reader :socket, :headers_sent
  attr_accessor :status_code

  def initialize(socket, &on_finished)
    @socket = socket
    @on_finished = on_finished
    reset!
  end

  def protocol
    nil
  end

  def reset!
    @status_code = 200
    @headers ? @headers.clear : (@headers = +'')
    @headers_sent = nil
  end

  def set_header(key, value)
    @headers << "#{key}: #{value}\r\n"
  end

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

  def write(data, finish = nil)
    unless @headers_sent
      set_header('Content-Length', data.bytesize) if data && finish
      send_headers
    end
    send(data, finish)
  end

  def finish(data = nil)
    write(data, true)
    @on_finished&.()
  end

  private

  def send(data, finish)
    @socket << data
  end

  def send_headers
    @socket << "HTTP/1.1 #{@status_code}\r\n#{@headers}\r\n"
    @headers_sent = true
  end
end
