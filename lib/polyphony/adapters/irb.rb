# frozen_string_literal: true

require 'polyphony'

module Kernel
  alias_method :gets, :orig_gets
end
