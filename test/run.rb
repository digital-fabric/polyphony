# frozen_string_literal: true

Dir.glob("#{__dir__}/test_*.rb").each do |path|
  require(path)
end
