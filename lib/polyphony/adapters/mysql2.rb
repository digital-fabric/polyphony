# frozen_string_literal: true

require_relative '../../polyphony'
require 'mysql2/client'

# Mysql2::Client overrides
Mysql2::Client.prepend(Module.new do
  def initialize(config)
    config[:async] = true
    super
    @io = ::IO.for_fd(socket)
  end

  def query(sql, **options)
    super
    Thread.current.agent.wait_io(@io, false)
    async_result
  end
end)
