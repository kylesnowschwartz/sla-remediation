# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class AppTest < Test
    def test_healthz_returns_ok
      get '/healthz'

      assert_equal 200, last_response.status
      assert_equal 'application/json', last_response.media_type
      assert_equal({ 'ok' => true }, JSON.parse(last_response.body))
    end
  end
end
