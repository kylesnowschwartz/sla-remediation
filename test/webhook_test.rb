# frozen_string_literal: true

require 'base64'
require 'logger'
require 'stringio'

require_relative 'test_helper'

module SLA
  class WebhookTest < Test
    SECRET = 'test-webhook-secret'
    REPO = 'kylesnowschwartz/superset'
    FIXTURES = File.expand_path('fixtures', __dir__)
    SESSIONS_URL = 'https://api.devin.ai/v3/organizations/org-test/sessions'
    PULLS_URL = "https://api.github.com/repos/#{REPO}/pulls".freeze
    REF_URL = "https://api.github.com/repos/#{REPO}/git/ref/heads/fix/urllib3-sla-4".freeze
    JSON_HEADER = { 'Content-Type' => 'application/json' }.freeze

    def setup
      ENV['SLA_WEBHOOK_SECRET'] = SECRET
      ENV['SLA_REPO'] = REPO
      ENV['DEVIN_PLAYBOOK_ID'] = 'pb_test'
      ENV.delete('SLA_AUTO_DISPATCH')
      DB[:sessions].delete
      DB[:findings].delete
      @log = StringIO.new
      App.set :policy, Policy.load(security_sla_text)
      App.set :delivery_log, Logger.new(@log)
      App.set :devin, DevinClient.new(api_key: 'test-key', org_id: 'org-test')
      App.set :github, GitHubClient.new(token: 'test-token')
      App.set :dispatch_out, StringIO.new
      stub_request(:post, SESSIONS_URL).to_return(status: 200, body: fixture('devin/create_session_response.json'),
                                                  headers: JSON_HEADER)
      stub_request(:get, PULLS_URL).with(query: { state: 'open', head: 'kylesnowschwartz:fix/urllib3-sla-4' })
                                   .to_return(status: 200, body: '[]', headers: JSON_HEADER)
      stub_request(:get, REF_URL).to_return(status: 404, body: '{"message":"Not Found"}', headers: JSON_HEADER)
    end

    def test_opened_then_labeled_records_one_finding
      deliver('github_issues_opened.json')

      assert_equal 200, last_response.status
      assert_equal({ 'result' => 'started' }, JSON.parse(last_response.body))

      deliver('github_issues_labeled.json')

      assert_equal 200, last_response.status
      assert_equal({ 'result' => 'duplicate' }, JSON.parse(last_response.body))

      assert_equal 1, DB[:findings].count
      finding = DB[:findings].first
      assert_equal 4, finding[:issue_number]
      assert_equal 'urllib3', finding[:package]
      assert_equal '2.4.0', finding[:pinned]
      assert_equal '2.7.0', finding[:fix_version]
      assert_equal 'high', finding[:severity]
      assert_equal 'pip-audit', finding[:source]
      assert_equal 'pypi', finding[:ecosystem]
      assert_equal 'test: webhook path (throwaway)', finding[:issue_title]
      assert_equal 'https://github.com/kylesnowschwartz/superset/issues/4', finding[:issue_url]
      assert_equal %w[PYSEC-2026-141 PYSEC-2026-1998 PYSEC-2026-1994 PYSEC-2026-1996], JSON.parse(finding[:advisories])
      assert_equal Time.utc(2026, 9, 2, 8, 25, 30), finding[:opened_at]
      assert_equal Time.utc(2026, 9, 4, 8, 25, 30), finding[:due_at]
      assert_nil finding[:closed_at]
      refute_nil finding[:created_at]
    end

    def test_ecosystem_from_the_finding_block_is_stored
      payload = JSON.parse(fixture('github/github_issues_opened.json'))
      payload['issue']['body'] = payload['issue']['body'].sub('source: pip-audit', "source: pip-audit\necosystem: npm")

      post_webhook(JSON.generate(payload))

      assert_equal 200, last_response.status
      assert_equal 'npm', DB[:findings].first[:ecosystem]
    end

    def test_opened_with_auto_dispatch_starts_one_session
      ENV['SLA_AUTO_DISPATCH'] = 'true'

      deliver('github_issues_opened.json')

      assert_equal 200, last_response.status
      assert_equal({ 'result' => 'started' }, JSON.parse(last_response.body))
      assert_requested :post, SESSIONS_URL, times: 1
      assert_equal 1, DB[:sessions].count
      assert_equal DB[:findings].first[:id], DB[:sessions].first[:finding_id]
      assert_equal '7cde046172a044b18c55ceeabe09e028', DB[:sessions].first[:devin_session_id]
      assert_match(/webhook event=issues action=opened issue=4 result=started dispatch=dispatched$/, @log.string)

      deliver('github_issues_labeled.json')

      assert_equal({ 'result' => 'duplicate' }, JSON.parse(last_response.body))
      assert_requested :post, SESSIONS_URL, times: 1
      assert_equal 1, DB[:sessions].count
    end

    def test_opened_without_auto_dispatch_records_only_the_finding
      deliver('github_issues_opened.json')

      assert_equal 200, last_response.status
      assert_not_requested :post, SESSIONS_URL
      assert_equal 1, DB[:findings].count
      assert_equal 0, DB[:sessions].count
      assert_match(/result=started dispatch=off$/, @log.string)
    end

    def test_auto_dispatch_of_an_unfixable_finding_creates_nothing
      ENV['SLA_AUTO_DISPATCH'] = 'true'
      payload = JSON.parse(fixture('github/github_issues_opened.json'))
      payload['issue']['body'] = payload['issue']['body'].sub('fix_version: 2.7.0', 'fix_version: null')

      post_webhook(JSON.generate(payload))

      assert_equal({ 'result' => 'started' }, JSON.parse(last_response.body))
      assert_not_requested :post, SESSIONS_URL
      assert_equal 0, DB[:sessions].count
      assert_match(/result=started dispatch=not_fixable$/, @log.string)
    end

    def test_auto_dispatch_failure_keeps_the_finding_and_logs_the_error
      ENV['SLA_AUTO_DISPATCH'] = 'true'
      stub_request(:post, SESSIONS_URL).to_return(status: 503, body: '{"detail":"unavailable"}',
                                                  headers: JSON_HEADER)

      deliver('github_issues_opened.json')

      assert_equal 200, last_response.status
      assert_equal({ 'result' => 'started' }, JSON.parse(last_response.body))
      assert_requested :post, SESSIONS_URL, times: 1
      assert_equal 1, DB[:findings].count
      assert_equal 0, DB[:sessions].count
      assert_match(/result=started dispatch=error \(Devin API returned 503: .*unavailable.*\)$/, @log.string)

      deliver('github_issues_labeled.json')

      assert_equal({ 'result' => 'duplicate' }, JSON.parse(last_response.body))
      assert_requested :post, SESSIONS_URL, times: 1
      assert_equal 0, DB[:sessions].count
    end

    def test_auto_dispatch_skips_a_finding_whose_fix_branch_exists
      ENV['SLA_AUTO_DISPATCH'] = 'true'
      stub_request(:get, REF_URL).to_return(status: 200, body: '{"ref":"refs/heads/fix/urllib3-sla-4"}',
                                            headers: JSON_HEADER)

      deliver('github_issues_opened.json')

      assert_equal({ 'result' => 'started' }, JSON.parse(last_response.body))
      assert_not_requested :post, SESSIONS_URL
      assert_equal 0, DB[:sessions].count
      assert_match(/result=started dispatch=already_dispatched$/, @log.string)
    end

    def test_closed_marks_the_finding_remediated
      deliver('github_issues_opened.json')

      deliver('github_issues_closed.json')

      assert_equal 200, last_response.status
      assert_equal({ 'result' => 'remediated' }, JSON.parse(last_response.body))
      assert_equal Time.utc(2026, 9, 2, 8, 25, 40), DB[:findings].first[:closed_at]
    end

    def test_closed_without_a_finding_is_ignored
      deliver('github_issues_closed.json')

      assert_equal 204, last_response.status
      assert_empty last_response.body
    end

    def test_tampered_body_is_rejected
      body = fixture('github/github_issues_opened.json')
      signature = Webhook::Signature.compute(SECRET, body)

      post_webhook(body.sub('"number": 4', '"number": 5'), signature: signature)

      assert_equal 401, last_response.status
      assert_equal 0, DB[:findings].count
    end

    def test_missing_signature_is_rejected
      post_webhook(fixture('github/github_issues_opened.json'), signature: nil)

      assert_equal 401, last_response.status
    end

    def test_ping_returns_ok
      post_webhook('{"zen":"Keep it logically awesome."}', event: 'ping')

      assert_equal 200, last_response.status
      assert_equal({ 'ok' => true }, JSON.parse(last_response.body))
    end

    def test_labeled_issue_without_a_finding_block_is_unprocessable
      payload = JSON.parse(fixture('github/github_issues_labeled.json'))
      payload['issue']['body'] = 'No finding block in this issue.'

      post_webhook(JSON.generate(payload))

      assert_equal 422, last_response.status
      assert_equal({ 'error' => 'issue body has no yaml finding block' }, JSON.parse(last_response.body))
      assert_equal 0, DB[:findings].count
    end

    def test_labeled_issue_with_unknown_severity_is_unprocessable
      payload = JSON.parse(fixture('github/github_issues_labeled.json'))
      payload['issue']['body'] = payload['issue']['body'].sub('severity: high', 'severity: moderate')

      post_webhook(JSON.generate(payload))

      assert_equal 422, last_response.status
      assert_match(/unknown severity "moderate"/, JSON.parse(last_response.body)['error'])
    end

    def test_unrelated_action_is_ignored
      payload = JSON.parse(fixture('github/github_issues_opened.json'))
      payload['action'] = 'edited'

      post_webhook(JSON.generate(payload))

      assert_equal 204, last_response.status
      assert_equal 0, DB[:findings].count
    end

    def test_opened_without_the_label_is_ignored
      payload = JSON.parse(fixture('github/github_issues_opened.json'))
      payload['issue']['labels'] = []

      post_webhook(JSON.generate(payload))

      assert_equal 204, last_response.status
      assert_equal 0, DB[:findings].count
    end

    def test_labeled_with_another_label_is_ignored
      payload = JSON.parse(fixture('github/github_issues_labeled.json'))
      payload['label']['name'] = 'bug'

      post_webhook(JSON.generate(payload))

      assert_equal 204, last_response.status
    end

    def test_other_events_are_ignored
      post_webhook(fixture('github/github_issues_opened.json'), event: 'issue_comment')

      assert_equal 204, last_response.status
    end

    def test_invalid_json_is_a_bad_request
      post_webhook('{not json')

      assert_equal 400, last_response.status
    end

    def test_signature_helper_matches_github_format
      signature = Webhook::Signature.compute('secret', 'body')

      assert_match(/\Asha256=[0-9a-f]{64}\z/, signature)
      assert Webhook::Signature.valid?('secret', 'body', signature)
      refute Webhook::Signature.valid?('secret', 'other', signature)
      refute Webhook::Signature.valid?('other', 'body', signature)
      refute Webhook::Signature.valid?('secret', 'body', '')
      refute Webhook::Signature.valid?('secret', 'body', nil)
    end

    private

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end

    def security_sla_text
      Base64.decode64(JSON.parse(fixture('github/github_contents_security_sla.json'))['content'])
    end

    def deliver(name)
      post_webhook(fixture(File.join('github', name)))
    end

    def post_webhook(body, event: 'issues', signature: Webhook::Signature.compute(SECRET, body))
      header 'X-GitHub-Event', event
      header 'X-Hub-Signature-256', signature
      post '/webhooks/github', body, 'CONTENT_TYPE' => 'application/json'
    end
  end
end
