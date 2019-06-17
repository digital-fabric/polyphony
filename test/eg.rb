# frozen_string_literal: true

module Kernel
  RE_CONST  = /^[A-Z]/.freeze
  RE_ATTR   = /^@(.+)$/.freeze

  def eg(hash)
    Module.new.tap do |m|
      s = m.singleton_class
      hash.each do |k, v|
        case k
        when RE_CONST
          m.const_set(k, v)
        when RE_ATTR
          m.instance_variable_set(k, v)
        else
          if v.respond_to?(:to_proc)
            s.define_method(k) { |*args| instance_exec(*args, &v) }
          else
            s.define_method(k) { v }
          end
        end
      end
    end
  end
end