# frozen_string_literal: true

export_default :Agent

Core  = import('./core')
ResourcePool = import('./resource_pool')

# Implements an HTTP agent
class Agent
  # Opts:
  #   keep_alive: true/false
  #   max_sockets: maximum sockets per host
  #   timeout: socket timeout
  def initialize(opts)
    @opts = opts
    @requestQueues = Hash.new { |h, k| h[k] = [] }
    @sockets = Hash.new { |h, k| h[k] = ResourcePool.new }
  end

  def request(request)
    Core.promise do |p|
      request[:_promise] = p

      host = host_from_request(request)
      @requestQueues[host]
    end
  end

  # @return [Promise]
  def connect(opts)
  end


end