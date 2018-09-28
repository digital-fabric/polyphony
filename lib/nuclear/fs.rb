# frozen_string_literal: true

export  :stat,
        :read

require 'fileutils'

ThreadPool = import('./thread_pool')

def stat(path)
  ThreadPool.process { File.stat(path) }
end

def read(*args)
  ThreadPool.process { IO.read(*args) }
end