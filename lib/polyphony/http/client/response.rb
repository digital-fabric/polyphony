# frozen_string_literal: true

export_default :Response

require 'json'

# HTTP response
class Response
  attr_reader :status_code, :headers

  def initialize(adapter, status_code, headers)
    @adapter = adapter
    @status_code = status_code
    @headers = headers
  end

  def body
    @body ||= @adapter.body
  end

  def each_chunk(&block)
    @adapter.each_chunk(&block)
  end

  def next_body_chunk
    @adapter.next_body_chunk
  end

  def json
    @json ||= ::JSON.parse(body)
  end
end
