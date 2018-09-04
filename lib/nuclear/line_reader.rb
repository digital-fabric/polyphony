# frozen_string_literal: true

export_default :LineReader

Concurrency = import('./concurrency')

class LineReader
  def initialize(source = nil)
    @source = source
    if source
      source.on(:data) { push(data) }
      source.on(:close) { close }
      source.on(:error) { |err| error(err) }
    end
    @read_buffer = +''
    @gets_separator = $/
  end

  def push(data)
    @read_buffer << data
    emit_lines
  end

  def emit_lines
    while line = string_gets(@read_buffer, @gets_separator)
      @lines_promise.resolve(line)
    end
  end

  def string_gets(s, sep = $/)
    idx = s.index(sep)
    idx && s.slice!(0, idx + sep.bytesize)
  end

  def lines
    Concurrency.promise(recurring: true) do |p|
      @lines_promise = p
    end
  end

  def close
    @lines_promise&.stop
  end

  def error(err)
    @lines.stop
    @lines.error(err)
  end
end
