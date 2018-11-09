# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def sleep_and_cancel
  puts "#{Time.now} going to sleep with cancel..."
  cancel_after(1) do
    puts "#{Time.now} outer cancel scope"
    cancel_after(10) do
      puts "#{Time.now} inner cancel scope"
      await sleep 60
    rescue Exception => e
      puts "#{Time.now} inner scope got error: #{e}"
      raise e
    end
  rescue Exception => e
    puts "#{Time.now} outer scope got error: #{e}"
  end
ensure
  puts "#{Time.now} woke up"
end

async def sleep_and_move_on
  puts "#{Time.now} going to sleep with move_on..."
  move_on_after(1) do
    puts "#{Time.now} outer cancel scope"
    move_on_after(10) do
      puts "#{Time.now} inner cancel scope"
      await sleep 60
      puts "#{Time.now} inner scope done"
    end
    puts "#{Time.now} outer scope done"
  end
  puts "#{Time.now} woke up"
end

spawn do
  await sleep_and_cancel
  puts
  await sleep_and_move_on
end