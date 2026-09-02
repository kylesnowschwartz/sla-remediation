# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class DevinClientTest < Minitest::Test
    ORG_ID = 'org-test'
    API_KEY = 'test-key'
    BASE = "https://api.devin.ai/v3/organizations/#{ORG_ID}".freeze
    FIXTURES = File.expand_path('fixtures/devin', __dir__)
    AUTH_HEADERS = { 'Authorization' => "Bearer #{API_KEY}", 'Accept' => 'application/json' }.freeze
    JSON_HEADERS = AUTH_HEADERS.merge('Content-Type' => 'application/json').freeze

    def setup
      @client = DevinClient.new(api_key: API_KEY, org_id: ORG_ID)
    end

    def test_list_repositories_uses_v3beta1_and_maps_structs
      url = "https://api.devin.ai/v3beta1/organizations/#{ORG_ID}/repositories"
      stub_fixture(:get, url, 'list_repositories.json')

      repos = @client.list_repositories

      assert_requested :get, url, headers: AUTH_HEADERS
      assert_equal %w[kylesnowschwartz/sla-remediation kylesnowschwartz/superset], repos.map(&:repo_path)
      assert_equal %w[sla-remediation superset], repos.map(&:repo_name)
      assert_equal %w[github.com github.com], repos.map(&:git_connection_host)
    end

    def test_create_session_posts_the_recorded_request_body
      stub_fixture(:post, "#{BASE}/sessions", 'create_session_response.json')
      request = JSON.parse(fixture('create_session_request.json'))

      session = @client.create_session(
        prompt: request['prompt'], title: request['title'], repos: request['repos'], tags: request['tags'],
        structured_output_schema: request['structured_output_schema'], max_acu_limit: request['max_acu_limit'],
        resumable: request['resumable']
      )

      assert_requested(:post, "#{BASE}/sessions", headers: JSON_HEADERS) { |req| JSON.parse(req.body) == request }
      assert_equal '7cde046172a044b18c55ceeabe09e028', session.session_id
      assert_equal 'new', session.status
      assert_nil session.status_detail
      assert_nil session.structured_output
      assert_empty session.pull_requests
    end

    def test_session_parses_fields_from_waiting_for_user_fixture
      stub_fixture(:get, "#{BASE}/sessions/7cde", 'get_session_waiting_for_user.json')

      session = @client.session('7cde')

      assert_requested :get, "#{BASE}/sessions/7cde", headers: AUTH_HEADERS
      assert_equal '7cde046172a044b18c55ceeabe09e028', session.session_id
      assert_equal 'https://app.devin.ai/sessions/7cde046172a044b18c55ceeabe09e028', session.url
      assert_equal 'running', session.status
      assert_equal 'waiting_for_user', session.status_detail
      assert_in_delta 0.0, session.acus_consumed
      assert_equal %w[sla-remediation spike], session.tags
      assert_equal Time.at(1_788_336_287).utc, session.created_at
      assert_equal Time.at(1_788_336_350).utc, session.updated_at
      assert_kind_of Time, session.created_at
    end

    def test_structured_output_object_stays_a_hash
      stub_fixture(:get, "#{BASE}/sessions/a", 'get_session_waiting_for_user.json')

      output = @client.session('a').structured_output

      assert_kind_of Hash, output
      assert_equal 'master', output['default_branch']
      assert_equal({ 'flask' => '2.3.3', 'urllib3' => '2.4.0', 'paramiko' => '3.5.1' }, output['pins'])
    end

    def test_structured_output_string_null_becomes_nil
      stub_fixture(:get, "#{BASE}/sessions/b", 'get_session_suspended_with_pr.json')

      assert_nil @client.session('b').structured_output
    end

    def test_structured_output_json_string_is_parsed
      session = DevinClient::Session.new('structured_output' => '{"ok":true}')

      assert_equal({ 'ok' => true }, session.structured_output)
    end

    def test_waiting_for_user_with_output_is_settled
      stub_fixture(:get, "#{BASE}/sessions/a", 'get_session_waiting_for_user.json')

      session = @client.session('a')

      assert_predicate session, :stopped?
      assert_predicate session, :reported?
      assert_predicate session, :settled?
      refute_predicate session, :stalled?
    end

    def test_suspended_with_pr_is_stopped_and_reported
      stub_fixture(:get, "#{BASE}/sessions/b", 'get_session_suspended_with_pr.json')

      session = @client.session('b')

      assert_predicate session, :stopped?
      assert_predicate session, :reported?
      assert_equal 1, session.pull_requests.size
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/2', session.pull_requests.first.pr_url
      assert_equal 'open', session.pull_requests.first.pr_state
    end

    def test_stopped_without_output_or_pr_is_stalled
      session = DevinClient::Session.new('status' => 'suspended', 'status_detail' => 'inactivity',
                                         'structured_output' => 'null', 'pull_requests' => [])

      assert_predicate session, :stalled?
      refute_predicate session, :settled?
    end

    def test_running_session_is_not_stopped
      session = DevinClient::Session.new('status' => 'running', 'status_detail' => nil)

      refute_predicate session, :stopped?
    end

    def test_messages_maps_structs_with_time
      stub_fixture(:get, "#{BASE}/sessions/7cde/messages", 'list_messages.json')

      messages = @client.messages('7cde')

      assert_requested :get, "#{BASE}/sessions/7cde/messages", headers: AUTH_HEADERS
      assert_equal 5, messages.size
      assert_equal %w[user devin devin devin devin], messages.map(&:source)
      assert_equal 'api', messages.first.origin
      assert_nil messages.last.origin
      assert_equal Time.at(1_788_336_287).utc, messages.first.created_at
      assert_match(/^Done\./, messages.last.message)
    end

    def test_messages_without_created_at_keep_nil_time
      body = { items: [{ source: 'devin', message: 'hi', created_at: nil }] }.to_json
      stub_request(:get, "#{BASE}/sessions/x/messages").to_return(status: 200, body: body, headers: json_header)

      assert_nil @client.messages('x').first.created_at
    end

    # Request-shape only: no recorded response exists for this endpoint.
    def test_send_message_posts_message_body
      stub_request(:post, "#{BASE}/sessions/7cde/messages").to_return(status: 200, body: '{}', headers: json_header)

      @client.send_message('7cde', 'Please continue.')

      assert_requested :post, "#{BASE}/sessions/7cde/messages",
                       headers: JSON_HEADERS, body: { message: 'Please continue.' }.to_json
    end

    def test_not_found_raises_devin_api_error
      stub_request(:get, "#{BASE}/sessions/missing")
        .to_return(status: 404, body: '{"detail":"Session not found"}', headers: json_header)

      error = assert_raises(DevinAPIError) { @client.session('missing') }

      assert_equal 404, error.status
      assert_equal({ 'detail' => 'Session not found' }, error.body)
      assert_kind_of SLA::Error, error
    end

    private

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end

    def json_header
      { 'Content-Type' => 'application/json' }
    end

    def stub_fixture(method, url, name)
      stub_request(method, url).to_return(status: 200, body: fixture(name), headers: json_header)
    end
  end
end
