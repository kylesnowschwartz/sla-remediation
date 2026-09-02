# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['SLA_DATABASE_URL'] = 'sqlite::memory:'

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'

require_relative '../lib/sla'

WebMock.disable_net_connect!

module SLA
  class Test < Minitest::Test
    include Rack::Test::Methods

    def app
      SLA::App
    end
  end
end
