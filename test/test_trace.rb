# frozen_string_literal: true

require_relative 'helper'
require 'polyphony/core/debug'

class TraceTest < MiniTest::Test
  def test_tracing_enabled
    events = []

    Thread.backend.trace_proc = proc { |*e|
      case e[0]
      when :schedule
        e = e[0..3]
      when :block
        e = e[0..1]
      when :unblock
        e = e[0..2]
      end
      events << e
    }
    snooze

    assert_equal [
      [:schedule, Fiber.current, nil, false],
      [:block, Fiber.current],
      [:unblock, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_2_fiber_trace
    events = []
    Thread.backend.trace_proc = proc { |*e|
      case e[0]
      when :schedule
        e = e[0..3]
      when :spin, :block
        e = e[0..1]
      when :unblock
        e = e[0..2]
      end
      events << e
    }

    f = spin { sleep 0; :byebye }
    l0 = __LINE__ + 1
    suspend
    sleep 0

    Thread.backend.trace_proc = nil
    
    assert_equal [
      [:spin, f],
      [:schedule, f, nil, false],
      [:block, Fiber.current],
      [:unblock, f, nil],
      [:block, f],
      [:enter_poll, f],
      [:schedule, f, nil, false],
      [:leave_poll, f],
      [:unblock, f, nil],
      [:terminate, f, :byebye],
      [:block, f],
      [:block, Fiber.current],
      [:enter_poll, Fiber.current],
      [:schedule, Fiber.current, nil, false],
      [:leave_poll, Fiber.current],
      [:unblock, Fiber.current, nil]
    ], events
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_event_firehose
    buffer = []
    Polyphony::Trace.start_event_firehose { |e| buffer << e }

    f1 = spin(:f1) do
      receive
    end

    f1 << :foo
    f1.await

    Thread.backend.trace_proc = nil

    buffer.each { |e| e.delete(:stamp); e.delete(:caller) }

    main = Fiber.current
    assert_equal(
      [
        { event: :spin,       fiber: f1,                  source_fiber: main  },
        { event: :schedule,   fiber: f1,    value: nil,   source_fiber: main  },
        { event: :block,      fiber: main                                     },
        { event: :unblock,    fiber: f1,    value: nil                        },
        { event: :schedule,   fiber: f1,    value: nil,   source_fiber: f1    },
        { event: :block,      fiber: f1,                                      },
        { event: :enter_poll                                                  },
        { event: :leave_poll                                                  },
        { event: :unblock,    fiber: f1,    value: nil                        },
        { event: :terminate,  fiber: f1,    value: :foo                       },
        { event: :schedule,   fiber: main,  value: nil,   source_fiber: f1    },
        { event: :block,      fiber: f1                                       },
        { event: :unblock,    fiber: main,  value: nil                        }
      ], buffer
    )
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_event_firehose_with_io
    r, w = IO.pipe
    Polyphony::Trace.start_event_firehose(w)

    f1 = spin(:f1) do
      receive
    end

    f1 << :foo
    f1.await

    Thread.backend.trace_proc = nil
    w.close

    log = r.read
    assert_equal 13, log.lines.size

    # TODO: make sure log is formatted correctly
  ensure
    Thread.backend.trace_proc = nil
  end

  def test_event_firehose_with_threaded_receiver
    buffer = []
    this = Fiber.current
    receiver = Thread.new {
      this << :ok
      loop {
        e = receive
        break if e == :stop
        buffer << e
      }
    }
    receive
    
    Polyphony::Trace.start_event_firehose { |e| receiver << e }

    f1 = spin(:f1) do
      receive
    end

    f1 << :foo
    f1.await

    Thread.backend.trace_proc = nil
    receiver << :stop
    receiver.await

    buffer.each { |e| e.delete(:stamp); e.delete(:caller) }

    main = Fiber.current
    assert_equal(
      [
        { event: :spin,       fiber: f1,                  source_fiber: main  },
        { event: :schedule,   fiber: f1,    value: nil,   source_fiber: main  },
        { event: :block,      fiber: main                                     },
        { event: :unblock,    fiber: f1,    value: nil                        },
        { event: :schedule,   fiber: f1,    value: nil,   source_fiber: f1    },
        { event: :block,      fiber: f1,                                      },
        { event: :enter_poll                                                  },
        { event: :leave_poll                                                  },
        { event: :unblock,    fiber: f1,    value: nil                        },
        { event: :terminate,  fiber: f1,    value: :foo                       },
        { event: :schedule,   fiber: main,  value: nil,   source_fiber: f1    },
        { event: :block,      fiber: f1                                       },
        { event: :unblock,    fiber: main,  value: nil                        }
      ], buffer
    )
  ensure
    Thread.backend.trace_proc = nil
  end

  # def test_event_firehose_with_reentrancy
  #   buffer = []
  #   Polyphony::Trace.start_event_firehose { |e| buffer << e }

  #   f1 = spin(:f1) do
  #     receive
  #   end

  #   f1 << :foo
  #   f1.await

  #   Thread.backend.trace_proc = nil
  #   buffer.each { |e| e.delete(:stamp); e.delete(:caller) }

  #   main = Fiber.current
  #   assert_equal(
  #     [
  #       { event: :spin,       fiber: f1,                  source_fiber: main  },
  #       { event: :schedule,   fiber: f1,    value: nil,   source_fiber: main  },
  #       { event: :block,      fiber: main                                     },
  #       { event: :unblock,    fiber: f1,    value: nil                        },
  #       { event: :schedule,   fiber: f1,    value: nil,   source_fiber: f1    },
  #       { event: :block,      fiber: f1,                                      },
  #       { event: :enter_poll                                                  },
  #       { event: :leave_poll                                                  },
  #       { event: :unblock,    fiber: f1,    value: nil                        },
  #       { event: :terminate,  fiber: f1,    value: :foo                       },
  #       { event: :schedule,   fiber: main,  value: nil,   source_fiber: f1    },
  #       { event: :block,      fiber: f1                                       },
  #       { event: :unblock,    fiber: main,  value: nil                        }
  #     ], buffer
  #   )
  # ensure
  #   Thread.backend.trace_proc = nil
  # end

end
