# frozen_string_literal: true

run(proc do |env|
  ['200', { 'Content-Type' => 'text/html' }, [
    env.select { |k, _v| k =~ /^[A-Z]/ }.inspect
  ]]
end)
