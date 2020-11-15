# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def do_work(client)
  result = yield
  client << result
rescue Exception => e
  client << e
end

$worker = Thread.new do
  Fiber.current.tag = :worker
  loop do
    (client, block) = receive
    do_work(client, &block)
  end
end

def process(&block)
  $worker.main_fiber << [Fiber.current, block]
  receive
end

sleep 0.1

p process { 1 + 1 }
p process { 42 ** 2 }