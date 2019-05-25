# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

resp = Polyphony::HTTP::Agent.get('https://google.com/')
p resp.body