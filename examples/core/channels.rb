# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

c1 = Nuclear.channel
c2 = Nuclear.channel

async! do
  async! do
    await Nuclear.sleep(1)
    c1 << "one"
  end

  async! do
    await Nuclear.sleep(2)
    c2 << "two"
  end

  2.times do
    Nuclear.select do |s|
      s.when ~c1 { |msg| puts "received msg" }
      s.when ~c2 { |msg| puts "received msg" }
    end
  end
end

      go func() {
          time.Sleep(1 * time.Second)
          c1 <- "one"
      }()
      go func() {
          time.Sleep(2 * time.Second)
          c2 <- "two"
      }()
  
  We’ll use select to await both of these values simultaneously, printing each one as it arrives.
    
  
      for i := 0; i < 2; i++ {
          select {
          case msg1 := <-c1:
              fmt.Println("received", msg1)
          case msg2 := <-c2:
              fmt.Println("received", msg2)
          }
      }
  }
  