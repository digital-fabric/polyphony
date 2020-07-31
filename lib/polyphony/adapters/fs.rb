# frozen_string_literal: true

require 'fileutils'

require_relative '../core/thread_pool'

::File.singleton_class.instance_eval do
  alias_method :orig_stat, :stat
  def stat(path)
    ThreadPool.process { orig_stat(path) }
  end
end

::IO.singleton_class.instance_eval do
  alias_method :orig_read, :read
  def read(path)
    ThreadPool.process { orig_read(path) }
  end
end
