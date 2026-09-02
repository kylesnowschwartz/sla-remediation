# frozen_string_literal: true

require 'stringio'

require_relative 'test_helper'

module SLA
  class DispatcherTest < Minitest::Test
    ORG_ID = 'org-test'
    REPO = 'kylesnowschwartz/superset'
    SESSIONS_URL = "https://api.devin.ai/v3/organizations/#{ORG_ID}/sessions".freeze
    PULLS_URL = "https://api.github.com/repos/#{REPO}/pulls".freeze
    PULLS_QUERY = { state: 'open', head: 'kylesnowschwartz:fix/urllib3-sla-4' }.freeze
    REF_URL = "https://api.github.com/repos/#{REPO}/git/ref/heads/fix/urllib3-sla-4".freeze
    GITHUB_API = /api\.github\.com/
    FIXTURES = File.expand_path('fixtures', __dir__)
    JSON_HEADER = { 'Content-Type' => 'application/json' }.freeze

    def setup
      DB[:sessions].delete
      DB[:findings].delete
      @out = StringIO.new
      @dispatcher = Dispatcher.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID),
                                   github: GitHubClient.new(token: 'test-token'), repo: REPO, out: @out)
      stub_request(:post, SESSIONS_URL).to_return(status: 200, body: fixture('devin/create_session_response.json'),
                                                  headers: JSON_HEADER)
      stub_request(:get, PULLS_URL).with(query: PULLS_QUERY).to_return(status: 200, body: '[]', headers: JSON_HEADER)
      stub_request(:get, REF_URL).to_return(status: 404, body: '{"message":"Not Found"}', headers: JSON_HEADER)
    end

    def test_dispatch_creates_one_session_and_records_it
      finding_id = record_finding(4)

      assert_equal :dispatched, @dispatcher.dispatch(4)

      assert_requested(:post, SESSIONS_URL, times: 1) { |req| session_request?(JSON.parse(req.body)) }
      assert_requested :get, PULLS_URL, query: PULLS_QUERY
      assert_requested :get, REF_URL
      assert_equal 1, DB[:sessions].count
      session = DB[:sessions].first

      assert_equal finding_id, session[:finding_id]
      assert_equal '7cde046172a044b18c55ceeabe09e028', session[:devin_session_id]
      assert_equal 'new', session[:status]
      assert_nil session[:status_detail]
      assert_equal Time.at(1_788_336_287).utc, session[:started_at]
      assert_in_delta Time.now.utc, session[:last_polled_at], 5
      assert_nil session[:finished_at]
      assert_equal "dispatched issue #4 → https://app.devin.ai/sessions/7cde046172a044b18c55ceeabe09e028\n",
                   @out.string
    end

    def test_second_dispatch_is_already_dispatched_without_a_post
      record_finding(4)
      @dispatcher.dispatch(4)
      WebMock.reset_executed_requests!

      assert_equal :already_dispatched, @dispatcher.dispatch(4)

      assert_not_requested :post, SESSIONS_URL
      assert_equal 1, DB[:sessions].count
    end

    # The other dispatch inserts its row between this one's check and its insert.
    def test_losing_the_insert_race_is_already_dispatched
      finding_id = record_finding(4)
      response = JSON.parse(fixture('devin/create_session_response.json'))
      racer = Object.new
      racer.define_singleton_method(:create_session) do |**|
        DB[:sessions].insert(finding_id: finding_id, devin_session_id: 'winner', status: 'running')
        DevinClient::Session.new(response)
      end

      github = GitHubClient.new(token: 'test-token')
      result = Dispatcher.new(db: DB, devin: racer, github: github, repo: REPO, out: @out).dispatch(4)

      assert_equal :already_dispatched, result
      assert_equal ['winner'], DB[:sessions].select_map(:devin_session_id)
    end

    def test_existing_fix_branch_is_already_dispatched_without_a_post
      record_finding(4)
      ref = { 'ref' => 'refs/heads/fix/urllib3-sla-4', 'object' => { 'sha' => 'abc123' } }
      stub_request(:get, REF_URL).to_return(status: 200, body: ref.to_json, headers: JSON_HEADER)

      assert_equal :already_dispatched, @dispatcher.dispatch(4)

      assert_not_requested :post, SESSIONS_URL
      assert_equal 0, DB[:sessions].count
      assert_equal "issue #4 already dispatched: branch fix/urllib3-sla-4 exists in #{REPO}\n", @out.string
    end

    def test_open_fix_pull_request_is_already_dispatched_without_a_post
      record_finding(4)
      pulls = [{ 'number' => 9, 'title' => 'fix: urllib3', 'html_url' => "https://github.com/#{REPO}/pull/9" }]
      stub_request(:get, PULLS_URL).with(query: PULLS_QUERY)
                                   .to_return(status: 200, body: pulls.to_json, headers: JSON_HEADER)

      assert_equal :already_dispatched, @dispatcher.dispatch(4)

      assert_not_requested :post, SESSIONS_URL
      assert_not_requested :get, REF_URL
      assert_equal 0, DB[:sessions].count
      assert_equal "issue #4 already dispatched: open pull request https://github.com/#{REPO}/pull/9\n", @out.string
    end

    def test_github_errors_other_than_404_propagate_without_a_post
      record_finding(4)
      stub_request(:get, REF_URL).to_return(status: 500, body: '{"message":"boom"}', headers: JSON_HEADER)

      error = assert_raises(GitHubAPIError) { @dispatcher.dispatch(4) }

      assert_equal 500, error.status
      assert_not_requested :post, SESSIONS_URL
      assert_equal 0, DB[:sessions].count
    end

    def test_finding_without_a_fix_version_is_not_fixable
      record_finding(5, package: 'paramiko', pinned: '3.5.1', fix_version: nil, severity: 'low')

      assert_equal :not_fixable, @dispatcher.dispatch(5)

      assert_not_requested :post, SESSIONS_URL
      assert_not_requested :get, GITHUB_API
      assert_equal 0, DB[:sessions].count
    end

    def test_unknown_issue_is_not_found
      assert_equal :not_found, @dispatcher.dispatch(99)

      assert_not_requested :post, SESSIONS_URL
      assert_not_requested :get, GITHUB_API
    end

    def test_preview_prints_the_prompt_and_payload_without_posting
      record_finding(4)

      assert_equal :previewed, @dispatcher.preview(4)

      assert_not_requested :post, SESSIONS_URL
      assert_not_requested :get, GITHUB_API
      assert_equal 0, DB[:sessions].count
      assert_includes @out.string, 'named `fix/urllib3-sla-4`'
      payload = JSON.parse(@out.string[@out.string.index('{')..])

      assert session_request?(payload)
    end

    def test_preview_of_an_unfixable_or_unknown_issue
      record_finding(5, fix_version: nil)

      assert_equal :not_fixable, @dispatcher.preview(5)
      assert_equal :not_found, @dispatcher.preview(99)
      assert_empty @out.string
    end

    private

    # Asserts every field of a create-session payload; true so it can be a WebMock request matcher.
    def session_request?(payload)
      assert_equal %w[prompt title repos tags resumable max_acu_limit structured_output_schema].sort, payload.keys.sort
      assert_equal 'test: webhook path (throwaway)', payload['title']
      assert_equal [REPO], payload['repos']
      assert_equal %w[sla-remediation issue-4], payload['tags']
      assert_equal 3, payload['max_acu_limit']
      assert_equal false, payload['resumable']
      assert_equal RemediationPrompt.schema, payload['structured_output_schema']
      assert_includes payload['prompt'], 'named `fix/urllib3-sla-4`'
      assert_includes payload['prompt'], 'due by 2026-09-04 08:25 UTC'
      true
    end

    def record_finding(issue_number, **overrides)
      issue = JSON.parse(fixture('github/github_issues_opened.json')).fetch('issue')
      finding = FindingBlock.parse(issue['body'])
      DB[:findings].insert({
        issue_number: issue_number, issue_title: issue['title'], issue_url: issue['html_url'],
        package: finding.package, pinned: finding.pinned, fix_version: finding.fix_version,
        severity: finding.severity, source: finding.source, ecosystem: finding.ecosystem,
        advisories: JSON.generate(finding.advisories),
        opened_at: Time.utc(2026, 9, 2, 8, 25, 30), due_at: Time.utc(2026, 9, 4, 8, 25, 30),
        created_at: Time.now.utc
      }.merge(overrides))
    end

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end
  end
end
