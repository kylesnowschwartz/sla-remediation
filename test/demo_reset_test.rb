# frozen_string_literal: true

require 'stringio'
require 'yaml'

require_relative 'test_helper'

module SLA
  class DemoResetTest < Minitest::Test
    REPO = 'kylesnowschwartz/superset'
    API = "https://api.github.com/repos/#{REPO}".freeze
    PULLS_URL = "#{API}/pulls".freeze
    ISSUES_URL = "#{API}/issues".freeze
    CONTENTS_URL = "#{API}/contents/requirements/base.txt".freeze
    FIX_REF_URL = "#{API}/git/refs/heads/fix/urllib3-sla-4".freeze
    JSON_HEADER = { 'Content-Type' => 'application/json' }.freeze
    PULLS_QUERY = { state: 'open', per_page: '100' }.freeze
    ISSUES_QUERY = { state: 'open', labels: 'sla-remediation', per_page: '100' }.freeze
    BLOB_SHA = '3d21ec53a331a6f037a91c368710b99387d012c1'
    SEEDS = <<~YAML
      repo_file: requirements/base.txt
      branch: master
      packages:
        urllib3:
          seeded: "2.4.0"
          upstream: "2.7.0"
        requests:
          seeded: "2.31.0"
          upstream: "2.33.0"
    YAML
    UPSTREAM_PINS = <<~TXT
      pandas==2.2.3
          # via superset
      requests==2.33.0
          # via superset
      urllib3==2.7.0
          # via requests
    TXT
    SEEDED_PINS = <<~TXT
      pandas==2.2.3
          # via superset
      requests==2.31.0
          # via superset
      urllib3==2.4.0
          # via requests
    TXT

    def setup
      DB[:sessions].delete
      DB[:findings].delete
      finding_id = DB[:findings].insert(issue_number: 4, package: 'urllib3', pinned: '2.4.0', fix_version: '2.7.0',
                                        severity: 'high', source: 'pip-audit', created_at: Time.now.utc)
      DB[:sessions].insert(finding_id: finding_id, devin_session_id: 'session-1', status: 'running')
      @out = StringIO.new
      @seeds = YAML.safe_load(SEEDS)
    end

    def test_happy_path_closes_restores_and_clears_everything
      stub_fork(pulls: [fix_pull, other_pull], issues: [scan_issue], pins: UPSTREAM_PINS)

      summary = reset.call

      assert_equal({ prs_closed: 1, branches_deleted: 1, issues_closed: 1, pins_restored: 2, rows_deleted: 2 }, summary)
      assert_requested :patch, "#{PULLS_URL}/9", body: { state: 'closed' }.to_json
      assert_requested :delete, FIX_REF_URL
      assert_requested :post, "#{ISSUES_URL}/4/comments",
                       body: { body: 'Closed by demo reset; the finding will be re-filed by the next scan.' }.to_json
      assert_requested :patch, "#{ISSUES_URL}/4", body: { state: 'closed' }.to_json
      assert_requested(:put, CONTENTS_URL) do |request|
        payload = JSON.parse(request.body)
        assert_equal 'chore: reseed known-vulnerable pins for the remediation demo', payload['message']
        assert_equal BLOB_SHA, payload['sha']
        assert_equal 'master', payload['branch']
        assert_equal SEEDED_PINS, Base64.strict_decode64(payload['content'])
        true
      end
      assert_equal 0, DB[:sessions].count
      assert_equal 0, DB[:findings].count
      assert_equal <<~OUT, @out.string
        closed pull request #9 (fix/urllib3-sla-4)
        deleted branch fix/urllib3-sla-4
        closed issue #4 [SLA high] urllib3 2.4.0 → 2.7.0
        restored urllib3==2.4.0, requests==2.31.0 in requirements/base.txt on master
        deleted 1 sessions and 1 findings
      OUT
    end

    def test_pull_requests_not_from_a_fix_branch_are_left_alone
      stub_fork(pulls: [other_pull], issues: [], pins: SEEDED_PINS)

      summary = reset.call

      assert_equal 0, summary[:prs_closed]
      assert_equal 0, summary[:branches_deleted]
      assert_not_requested :patch, %r{/pulls/}
      assert_not_requested :delete, %r{/git/refs/}
      assert_includes @out.string, "no open fix/ pull requests\n"
    end

    def test_issues_with_other_labels_are_left_alone
      stub_fork(pulls: [], issues: [], pins: SEEDED_PINS)
      stub_request(:get, ISSUES_URL).with(query: { state: 'open', labels: 'policy', per_page: '100' })
                                    .to_return(status: 200, body: [policy_issue].to_json, headers: JSON_HEADER)

      summary = reset.call

      assert_equal 0, summary[:issues_closed]
      assert_not_requested :patch, "#{ISSUES_URL}/1"
      assert_not_requested :post, "#{ISSUES_URL}/1/comments"
      assert_requested :get, ISSUES_URL, query: ISSUES_QUERY
      assert_not_requested :get, ISSUES_URL, query: { state: 'open', labels: 'policy', per_page: '100' }
      assert_includes @out.string, "no open sla-remediation issues\n"
    end

    def test_pins_already_seeded_means_no_commit
      stub_fork(pulls: [], issues: [], pins: SEEDED_PINS)

      summary = reset.call

      assert_equal 0, summary[:pins_restored]
      assert_not_requested :put, CONTENTS_URL
      assert_includes @out.string, "requirements/base.txt already has the seeded pins\n"
    end

    def test_dry_run_only_reads_and_deletes_no_rows
      stub_fork(pulls: [fix_pull, other_pull], issues: [scan_issue], pins: UPSTREAM_PINS)

      summary = reset(dry_run: true).call

      assert_equal({ prs_closed: 1, branches_deleted: 1, issues_closed: 1, pins_restored: 2, rows_deleted: 2 }, summary)
      assert_requested :get, PULLS_URL, query: PULLS_QUERY
      assert_requested :get, ISSUES_URL, query: ISSUES_QUERY
      assert_requested :get, CONTENTS_URL, query: { ref: 'master' }
      assert_not_requested :patch, /api\.github\.com/
      assert_not_requested :post, /api\.github\.com/
      assert_not_requested :put, /api\.github\.com/
      assert_not_requested :delete, /api\.github\.com/
      assert_equal 1, DB[:sessions].count
      assert_equal 1, DB[:findings].count
      assert_equal <<~OUT, @out.string
        would close pull request #9 (fix/urllib3-sla-4)
        would delete branch fix/urllib3-sla-4
        would close issue #4 [SLA high] urllib3 2.4.0 → 2.7.0
        would restore urllib3==2.4.0, requests==2.31.0 in requirements/base.txt on master
        would delete 1 sessions and 1 findings
      OUT
    end

    def test_a_second_run_finds_nothing_and_reports_zeros
      stub_fork(pulls: [fix_pull], issues: [scan_issue], pins: UPSTREAM_PINS)
      reset.call
      WebMock.reset!
      stub_fork(pulls: [], issues: [], pins: SEEDED_PINS)
      @out.truncate(0)
      @out.rewind

      summary = reset.call

      assert_equal({ prs_closed: 0, branches_deleted: 0, issues_closed: 0, pins_restored: 0, rows_deleted: 0 }, summary)
      assert_not_requested :patch, /api\.github\.com/
      assert_not_requested :post, /api\.github\.com/
      assert_not_requested :put, /api\.github\.com/
      assert_not_requested :delete, /api\.github\.com/
      assert_equal <<~OUT, @out.string
        no open fix/ pull requests
        no open sla-remediation issues
        requirements/base.txt already has the seeded pins
        database already empty
      OUT
    end

    private

    def reset(dry_run: false)
      DemoReset.new(github: GitHubClient.new(token: 'test-token'), repo: REPO, db: DB, seeds: @seeds, out: @out,
                    dry_run: dry_run)
    end

    # The reads every run makes, plus the writes the happy path makes, in the
    # shape GitHub's REST API answers them (only the fields the code reads).
    def stub_fork(pulls:, issues:, pins:)
      stub_request(:get, PULLS_URL).with(query: PULLS_QUERY)
                                   .to_return(status: 200, body: pulls.to_json, headers: JSON_HEADER)
      stub_request(:patch, "#{PULLS_URL}/9")
        .to_return(status: 200, body: fix_pull.merge('state' => 'closed').to_json, headers: JSON_HEADER)
      stub_request(:delete, FIX_REF_URL).to_return(status: 204, body: '')
      stub_request(:get, ISSUES_URL).with(query: ISSUES_QUERY)
                                    .to_return(status: 200, body: issues.to_json, headers: JSON_HEADER)
      stub_request(:post, "#{ISSUES_URL}/4/comments")
        .to_return(status: 201, body: { 'id' => 1, 'html_url' => "#{ISSUES_URL}/4#issuecomment-1" }.to_json,
                   headers: JSON_HEADER)
      stub_request(:patch, "#{ISSUES_URL}/4")
        .to_return(status: 200, body: scan_issue.merge('state' => 'closed').to_json, headers: JSON_HEADER)
      stub_request(:get, CONTENTS_URL).with(query: { ref: 'master' })
                                      .to_return(status: 200, body: contents_body(pins), headers: JSON_HEADER)
      stub_request(:put, CONTENTS_URL).to_return(status: 200, body: update_body, headers: JSON_HEADER)
    end

    def fix_pull
      { 'number' => 9, 'title' => 'fix(deps): bump urllib3 2.4.0 -> 2.7.0', 'state' => 'open',
        'html_url' => "https://github.com/#{REPO}/pull/9", 'head' => { 'ref' => 'fix/urllib3-sla-4' } }
    end

    def other_pull
      { 'number' => 2, 'title' => 'chore: unrelated work', 'state' => 'open',
        'html_url' => "https://github.com/#{REPO}/pull/2", 'head' => { 'ref' => 'chore/unrelated' } }
    end

    def scan_issue
      { 'number' => 4, 'title' => '[SLA high] urllib3 2.4.0 → 2.7.0', 'state' => 'open',
        'body' => "```yaml\npackage: urllib3\n```", 'html_url' => "https://github.com/#{REPO}/issues/4",
        'labels' => [{ 'name' => 'sla-remediation' }] }
    end

    def policy_issue
      { 'number' => 1, 'title' => 'Security SLA policy', 'state' => 'open', 'body' => 'See SECURITY-SLA.md',
        'html_url' => "https://github.com/#{REPO}/issues/1", 'labels' => [{ 'name' => 'policy' }] }
    end

    def contents_body(text)
      { 'type' => 'file', 'encoding' => 'base64', 'path' => 'requirements/base.txt', 'sha' => BLOB_SHA,
        'content' => Base64.encode64(text) }.to_json
    end

    def update_body
      { 'content' => { 'path' => 'requirements/base.txt', 'sha' => 'a'.ljust(40, 'b') },
        'commit' => { 'sha' => 'c'.ljust(40, 'd'), 'html_url' => "https://github.com/#{REPO}/commit/cddd" } }.to_json
    end
  end
end
