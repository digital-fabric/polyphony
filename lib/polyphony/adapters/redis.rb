# frozen_string_literal: true

require_relative '../../polyphony'

require 'redis-client'

class RedisClient
  class RubyConnection
    class BufferedIO
      def fill_buffer(strict, size = @chunk_size)
        remaining = size
        empty_buffer = @offset >= @buffer.bytesize

        loop do
          max_read = [remaining, @chunk_size].max
          bytes = if empty_buffer
            @io.readpartial(max_read, @buffer)
          else
            @io.readpartial(max_read)
          end

          raise Errno::ECONNRESET if bytes.nil?

          if empty_buffer
            @offset = 0
            empty_buffer = false
          else
            @buffer << bytes
          end
          remaining -= bytes.bytesize
          return if !strict || remaining <= 0
        end
      end
    end
  end
end
