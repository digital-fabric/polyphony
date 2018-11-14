# frozen_string_literal: true

export_default :ServerTask

Channel = import('./core/channel')
Task    = import('./core/task')

class ServerTask
  def initialize
    super {
      loop {
        message = await @mailbox.receive
        handle(message)
      }
    }
    @mailbox = Channel.new
  end
end