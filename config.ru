# frozen_string_literal: true

require_relative 'lib/sla'

SLA::Boot.start_tracker unless ENV['RACK_ENV'] == 'test'

run SLA::App
