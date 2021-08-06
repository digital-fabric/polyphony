# frozen_string_literal: true

require 'polyphony/extensions/debug'

module Polyphony
  TP_EVENTS = [
    :line,
    :call,
    :return,
    :b_call,
    :b_return
  ]    

  def self.start_debug_server(socket_path)
    server = DebugServer.new(socket_path)
    controller = DebugController.new(server)      
    trace = TracePoint.new(*TP_EVENTS) { |tp| controller.handle_tp(trace, tp) }
    trace.enable

    at_exit do
      puts "program terminated"
      trace.disable
      server.stop
    end
  end

  class DebugController
    def initialize(server)
      @server = server
      @server.wait_for_client
      @control_fiber = Fiber.new { |f| control_loop(f) }
      puts "control_fiber: #{@control_fiber.inspect}"
      @control_fiber.transfer Fiber.current
      trace :control_fiber_ready
    end

    def control_loop(source_fiber)
      @peer = source_fiber
      cmd = { kind: :initial }
      loop do
        cmd = send(:"cmd_#{cmd[:kind]}", cmd)
      end
    end

    POLYPHONY_LIB_DIR = File.expand_path('..', __dir__)

    def next_trace_event
      @peer.transfer
    end

    def next_command(event)
      while true
        cmd = parse_command(@server.interact_with_client(event))
        return cmd if cmd

        event = { instruction: "Type 'help' for list of commands" }
      end
    end

    def parse_command(cmd)
      case cmd
      when /^(step|s)$/
        { kind: :step }
      when /^(help|h)$/
        { kind: :help }
      else
        nil
      end
    end

    def cmd_initial(cmd)
      next_command(nil)
    end
    
    def cmd_step(cmd)
      tp = nil
      fiber = nil
      while true
        event = next_trace_event
        @peer = event[:fiber]
        if event[:kind] == :line && event[:path] !~ /#{POLYPHONY_LIB_DIR}/
          return next_command(event)
        end
      end
    rescue => e
      trace "Uncaught error: #{e.inspect}"
      @trace&.disable
    end

    def cmd_help(cmd)
      next_command(show: :help)
    end

    def handle_tp(trace, tp)
      return if Thread.current == @server.thread
      return if Fiber.current == @control_fiber

      event = {
        fiber: Fiber.current,
        kind: tp.event,
        path: tp.path,
        lineno: tp.lineno
      }
      @control_fiber.transfer(event)
    end
  end

  class DebugServer
    attr_reader :thread

    def initialize(socket_path)
      @socket_path = socket_path
      @fiber = Fiber.current
      start_server_thread
    end

    def start_server_thread
      @thread = Thread.new do
        puts("Listening on #{@socket_path}")
        FileUtils.rm(@socket_path) if File.exists?(@socket_path)
        socket = UNIXServer.new(@socket_path)
        loop do
          @client = socket.accept
        end
      end
    end

    def stop
      @thread.kill
    end

    def handle_client(client)
      @client = client
    end

    def wait_for_client
      trace "wait_for_client"
      sleep 0.1 until @client
      trace "  got client!"
      msg = @client.gets
      @client.puts msg
    end

    def interact_with_client(event)
      @client&.orig_write "#{event.inspect}\n"
      @client&.orig_gets&.chomp
    rescue SystemCallError
      nil
    rescue => e
      trace "Error in interact_with_client: #{e.inspect}"
      e.backtrace[0..3].each { |l| trace l }
      @client = nil
    end
  end
end
