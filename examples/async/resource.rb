# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')


def use_resource(resource)
  Nuclear.await Nuclear.sleep(1)
  puts "#{Time.now} done with #{resource.inspect}"
end

resource_count = 0
Pool = Nuclear::ResourcePool.new(limit: 3) {
  :"resource#{resource_count += 1}"
}

10.times do
  Nuclear.async do
    Pool.use { |r| use_resource(r) }
  end
end