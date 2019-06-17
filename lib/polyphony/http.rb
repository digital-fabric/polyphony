# frozen_string_literal: true

require_relative '../polyphony'

module Polyphony
  module HTTP
    auto_import(
      Agent:      './http/agent',
      Rack:       './http/server/rack',
      Server:     './http/server',
    )
  end
end

export_default Polyphony::HTTP
