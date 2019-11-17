# frozen_string_literal: true

Dir.glob("#{__dir__}/test_*.rb").each { |path|
  require(path) unless path =~ /http/
}