# frozen_string_literal: true

require 'polyphony/extensions/debug'

module Polyphony
  class DebugServer
    TP_EVENTS = [
      :line,
      :call,
      :return,
      :b_call,
      :b_return
    ]
    
    
    def self.start(socket_path)
      server = self.new(socket_path)
      server.start
    
      trace = TracePoint.new(*TP_EVENTS) { |tp| server.handle_tp(trace, tp) }
      trace.enable

      at_exit do
        puts "program terminated"
        trace.disable
        server.stop
      end
    end

    def initialize(socket_path)
      @socket_path = socket_path
      @fiber = Fiber.current
      @controller = spin { control_loop }
      puts "@fiber: #{@fiber.inspect}"
    end

    def start
      fiber = Fiber.current
      @server = spin(:pdbg_server) do
        puts("Listening on #{@socket_path}")
        FileUtils.rm(@socket_path) if File.exists?(@socket_path)
        socket = UNIXServer.new(@socket_path)
        fiber << :ready
        id = 0
        socket.accept_loop do |client|
          puts "accepted connection"
          handle_client(client)
        end
      end
      receive
    end

    def stop
      @server.terminate
      @controller.terminate
    end

    POLYPHONY_LIB_DIR = File.expand_path('../..', __dir__)
    def handle_client(client)
      @client = client
      puts "trace enabled"
    end

    def control_loop
      @cmd = :step
      loop do
        case @cmd
        when :step
          step
        end
      end
    end

    def step
      tp = nil
      while true
        sender, event = receive
        if sender == @fiber && event[:kind] == :line && event[:path] !~ /#{POLYPHONY_LIB_DIR}/
          interact_with_client(event)
          sender << :ok
          return
        end
          
        sender << :ok
      end
    rescue => e
      puts "Uncaught error: #{e.inspect}"
      @trace&.disable
      @client = nil
    end

    def interact_with_client(event)
      @client.puts event.inspect
      result = @client.gets&.chomp
    end

    def handle_tp(trace, tp)
      return if @in_handle_tp

      process_tp(trace, tp)
    end

    def process_tp(trace, tp)
      @in_handle_tp = true
      if !@client
        wait_for_client
      end

      @controller << [Fiber.current, {
        kind: tp.event,
        path: tp.path,
        lineno: tp.lineno
      }]
      receive
    ensure
      @in_handle_tp = nil
    end

    def wait_for_client
      puts "wait_for_client"
      sleep 0.1 until @client
      puts "  got client!"
      msg = @client.gets
      @client.puts msg
    end
  end
end
