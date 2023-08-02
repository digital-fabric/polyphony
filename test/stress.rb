# frozen_string_literal: true

count = ARGV[0] ? ARGV[0].to_i : 100
test_name = ARGV[1]

$test_cmd = +'ruby test/run.rb --verbose'
if test_name
  $test_cmd << " --name #{test_name}"
end

puts '*' * 40
puts
puts $test_cmd
puts

@failure_count = 0

def run_test(count)
  puts "#{count}: running tests..."
  # sleep 1
  system($test_cmd)
  puts

  if $?.exitstatus != 0
    puts "Test failed (#{count})..."
    exit!
    @failure_count += 1
  end
end

trap('INT') { exit! }
t0 = Time.now
count.times do |i|
  run_test(i + 1)
end
elapsed = Time.now - t0
puts format(
  "Ran %d tests in %f seconds (%f per test), failures: %d",
  count,
  elapsed,
  elapsed / count,
  @failure_count
)