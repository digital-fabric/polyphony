module ::Kernel
  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.size > 1 && args.first.is_a?(String)
      format("%s: %p\n", args.shift, args.size == 1 ? args.first : args)
    elsif args.size == 1 && args.first.is_a?(String)
      "#{args.first}\n"
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end
end

module Polyphony
  module Trace
    class << self
      def start_event_firehose(io = nil, &block)
        Thread.backend.trace_proc = firehose_proc(io, block)
      end

      private

      def firehose_proc(io, block)
        if io
          ->(*e) { io.orig_write("#{trace_event_info(e).inspect}\n") }
        elsif block
          ->(*e) { block.(trace_event_info(e)) }
        else
          raise "Please provide an io or a block"
        end
      end

      def trace_event_info(e)
        {
          stamp: format_current_time,
          event: e[0]
        }.merge(
          send(:"event_props_#{e[0]}", e)
        )
      end
      
      def format_trace_event_message(e)
        props = send(:"event_props_#{e[0]}", e).merge(
          timestamp: format_current_time,
          event: e[0]
        )
        # templ = send(:"event_format_#{e[0]}", e)

        # msg = format("%<timestamp>s #{templ}\n", **props)
      end

      def format_current_time
        Time.now.strftime('%Y-%m-%d %H:%M:%S')
      end

      def generic_event_format
        '%<event>-12.12s'
      end

      def fiber_event_format
        "#{generic_event_format} %<fiber>-44.44s"
      end

      def event_props_enter_poll(e)
        {}
      end

      def event_format_enter_poll(e)
        generic_event_format
      end

      def event_props_leave_poll(e)
        {}
      end

      def event_format_leave_poll(e)
        generic_event_format
      end

      def event_props_schedule(e)
        {
          fiber: e[1],
          value: e[2],
          caller: e[4],
          source_fiber: Fiber.current
        }
      end

      def event_format_schedule(e)
        "#{fiber_event_format} %<value>-24.24p %<caller>-120.120s <= %<origin_fiber>s"
      end

      def event_props_unblock(e)
        {
          fiber: e[1],
          value: e[2],
          caller: e[3],
        }
      end

      def event_format_unblock(e)
        "#{fiber_event_format} %<value>-24.24p %<caller>-120.120s"
      end

      def event_props_terminate(e)
        {
          fiber: e[1],
          value: e[2],
        }
      end

      def event_format_terminate(e)
        "#{fiber_event_format} %<value>-24.24p"
      end

      def event_props_block(e)
        {
          fiber: e[1],
          caller: e[2]
        }
      end

      def event_format_block(e)
        "#{fiber_event_format} #{' ' * 24} %<caller>-120.120s"
      end

      def event_props_spin(e)
        {
          fiber: e[1],
          caller: e[2],
          source_fiber: Fiber.current
        }
      end

      def event_format_spin(e)
        "#{fiber_event_format} #{' ' * 24} %<caller>-120.120s <= %<origin_fiber>s"
      end

      def fibe_repr(fiber)
        format("%-6x %-20.20s %-10.10s", fiber.object_id, fiber.tag, "(#{fiber.state})")
      end

      def fiber_compact_repr(fiber)
        if fiber.tag
          format("%-6x %-.20s %-.10s", fiber.object_id, fiber.tag, "(#{fiber.state})")
        else
          format("%-6x %-.10s", fiber.object_id, "(#{fiber.state})")
        end
      end

      def caller_repr(c)
       c.map { |i| i.gsub('/home/sharon/repo/polyphony/lib/polyphony', '') }.join('  ')
      end
    end
  end
end
