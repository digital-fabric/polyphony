# frozen_string_literal: true

export  :stat,
        :read

require 'fileutils'

ThreadPool = import('./core/thread_pool')

::File.singleton_class.instance_eval do
  alias_method :orig_stat, :stat
  def stat(path)
    if Fiber.current.root?
      orig_stat(path)
    else
      ThreadPool.process { orig_stat(path) }
    end
  end
end

::IO.singleton_class.instance_eval do
  alias_method :orig_read, :read
  def read(path)
    if Fiber.current.root?
      orig_read(path)
    else
      ThreadPool.process { orig_read(path) }
    end
  end
end
