# frozen_string_literal: true

count = ARGV[0] ? ARGV[0].to_i : 100

TEST_CMD = 'ruby test/run.rb'

def run_test(count)
  puts "#{count}: running tests..."
  system(TEST_CMD)
  return if $?.exitstatus == 0

  exit!
end

trap('INT') { exit! }
count.times { |i| run_test(i + 1) }
