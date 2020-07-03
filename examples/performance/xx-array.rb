X = ARGV[0] ? ARGV[0].to_i : 10
a = (1..X).to_a

Y = 1_000_000
t0 = Time.now
Y.times do
  i = a.shift
  a.push i
end

puts "rate: #{Y / (Time.now - t0)}"
