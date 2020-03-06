# frozen_string_literal: true

@count = 0

def run_tests
  @count += 1
  puts "!(#{@count})"
  # output = `ruby test/test_thread.rb -n test_thread_inspect`
  system('ruby test/run.rb')
  return if $?.exitstatus == 0

  exit!
  # puts
  # puts output
  # exit!
end

loop {
  run_tests
}