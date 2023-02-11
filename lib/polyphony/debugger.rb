# frozen_string_literal: true

require 'polyphony/core/debug'

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
      Kernel.trace "program terminated"
      trace.disable
      server.stop
    end
  end

  class DebugController
    def initialize(server)
      @server = server
      @server.wait_for_client
      @state = { fibers: {} }
      @control_fiber = Fiber.new { |f| control_loop(f) }
      @control_fiber.transfer Fiber.current
    end

    def control_loop(source_fiber)
      @peer = source_fiber
      cmd = { cmd: :initial }
      loop do
        cmd = send(:"cmd_#{cmd[:cmd]}", cmd)
      end
    end

    POLYPHONY_LIB_DIR = File.expand_path('..', __dir__)

    def get_next_trace_event
      @peer.transfer.tap { |e| update_state(e) }
    end

    def update_state(event)
      trace update_state: event
      @state[:fiber] = event[:fiber]
      @state[:path] = event[:path]
      @state[:lineno] = event[:lineno]
      update_fiber_state(event)
    end

    def update_fiber_state(event)
      fiber_state = @state[:fibers][event[:fiber]] ||= { stack: [] }
      case event[:kind]
      when :call, :c_call, :b_call
        fiber_state[:stack] << event
      when :return, :c_return, :b_return
        fiber_state[:stack].pop
      end
      fiber_state[:binding] = event[:binding]
      fiber_state[:path] = event[:path]
      fiber_state[:lineno] = event[:lineno]
    end

    def state_presentation(state)
      {
        fiber:  fiber_id(state[:fiber]),
        path:   state[:path],
        lineno: state[:lineno]
      }
    end

    def fiber_id(fiber)
      {
        object_id: fiber.object_id,
        tag: fiber.tag
      }
    end

    def fiber_representation(fiber)
      {
        object_id: fiber.object_id,
        tag: fiber.tag,
        parent: fiber.parent && fiber_id(fiber.parent),
        children: fiber.children.map { |c| fiber_id(c) }
      }
    end

    def get_next_command(info)
      @server.get_command(info)
    end

    def cmd_initial(cmd)
      get_next_command(nil)
    end

    def info_listing(state)
      {
        kind: :listing,
        fiber: fiber_id(state[:fiber]),
        path: state[:path],
        lineno: state[:lineno]
      }
    end

    def info_state(state)
      info_listing(state).merge(
        kind: :state,
        fibers: info_fiber_states(state[:fibers])
      )
    end

    def info_fiber_states(fiber_states)
      fiber_states.inject({}) do |h, (f, s)|
        h[fiber_id(f)] = {
          stack: s[:stack].map { |e| { path: e[:path], lineno: e[:lineno] } }
        }
        h
      end
    end

    def cmd_step(cmd)
      tp = nil
      fiber = nil
      while true
        event = get_next_trace_event
        @peer = event[:fiber]
        if event[:kind] == :line && event[:path] !~ /#{POLYPHONY_LIB_DIR}/
          return get_next_command(info_listing(@state))
        end
      end
    rescue => e
      trace "Uncaught error: #{e.inspect}"
      @trace&.disable
    end

    def cmd_help(cmd)
      get_next_command(kind: :help)
    end

    def cmd_list(cmd)
      get_next_command(info_listing(@state))
    end

    def cmd_state(cmd)
      get_next_command(info_state(@state))
    end

    def handle_tp(trace, tp)
      return if Thread.current == @server.thread
      return if Fiber.current == @control_fiber

      kind = tp.event
      event = {
        fiber: Fiber.current,
        kind: kind,
        path: tp.path,
        lineno: tp.lineno,
        binding: tp.binding
      }
      case kind
      when :call, :c_call, :b_call
        event[:method_id] = tp.method_id
        event[:parameters] = tp.parameters
      when :return, :c_return, :b_return
        event[:method_id] = tp.method_id
        event[:return_value] = tp.return_value
      end
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
        FileUtils.rm(@socket_path) if File.exist?(@socket_path)
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
      sleep 0.1 until @client
      msg = @client.gets
      @client.puts msg
    end

    def get_command(info)
      @client&.orig_write "#{info.inspect}\n"
      cmd = @client&.orig_gets&.chomp
      eval(cmd)
    rescue SystemCallError
      nil
    rescue => e
      trace "Error in interact_with_client: #{e.inspect}"
      e.backtrace[0..3].each { |l| trace l }
      @client = nil
    end
  end
end
