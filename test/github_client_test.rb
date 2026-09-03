# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class GitHubClientTest < Minitest::Test
    TOKEN = 'test-token'
    FIXTURES = File.expand_path('fixtures/github', __dir__)
    CONTENTS_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/contents/SECURITY-SLA.md'
    ISSUES_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/issues'
    ADVISORY_URL = 'https://api.github.com/advisories/GHSA-qccp-gfcp-xxvc'
    PULLS_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/pulls'
    REF_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/git/ref/heads/fix/urllib3-sla-4'
    REFS_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/git/refs/heads/fix/urllib3-sla-4'
    REQUIREMENTS_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/contents/requirements/base.txt'
    HEADERS = {
      'Authorization' => "Bearer #{TOKEN}",
      'Accept' => 'application/vnd.github+json',
      'X-GitHub-Api-Version' => '2022-11-28'
    }.freeze

    def setup
      @client = GitHubClient.new(token: TOKEN)
    end

    def test_file_contents_decodes_the_base64_content
      stub_request(:get, CONTENTS_URL).with(query: { ref: 'master' })
                                      .to_return(status: 200, body: fixture('github_contents_security_sla.json'),
                                                 headers: json_header)

      text = @client.file_contents('kylesnowschwartz/superset', 'SECURITY-SLA.md', ref: 'master')

      assert_requested :get, CONTENTS_URL, query: { ref: 'master' }, headers: HEADERS
      assert_equal Encoding::UTF_8, text.encoding
      assert_match(/\A# Security SLA for dependency vulnerabilities\n/, text)
      assert_includes text, "```yaml\nsla_days:\n  critical: 2\n  high: 2\n  medium: 14\n  low: 30\n```"
    end

    def test_file_contents_rejects_unknown_encodings
      body = { 'encoding' => 'none', 'content' => '' }.to_json
      stub_request(:get, CONTENTS_URL).with(query: { ref: 'master' })
                                      .to_return(status: 200, body: body, headers: json_header)

      assert_raises(SLA::Error) { @client.file_contents('kylesnowschwartz/superset', 'SECURITY-SLA.md', ref: 'master') }
    end

    def test_not_found_raises_github_api_error
      stub_request(:get, CONTENTS_URL).with(query: { ref: 'missing' })
                                      .to_return(status: 404, body: '{"message":"Not Found"}', headers: json_header)

      error = assert_raises(GitHubAPIError) do
        @client.file_contents('kylesnowschwartz/superset', 'SECURITY-SLA.md', ref: 'missing')
      end

      assert_equal 404, error.status
      assert_equal({ 'message' => 'Not Found' }, error.body)
      assert_kind_of SLA::Error, error
    end

    def test_advisory_reads_the_recorded_advisory
      stub_request(:get, ADVISORY_URL).to_return(status: 200, body: fixture('advisories/GHSA-qccp-gfcp-xxvc.json'),
                                                 headers: json_header)

      advisory = @client.advisory('GHSA-qccp-gfcp-xxvc')

      assert_requested :get, ADVISORY_URL, headers: HEADERS
      assert_equal 'GHSA-qccp-gfcp-xxvc', advisory.ghsa_id
      assert_equal 'CVE-2026-44431', advisory.cve_id
      assert_equal 'high', advisory.severity
      assert_equal 'urllib3: Sensitive headers forwarded across origins in proxied low-level redirects',
                   advisory.summary
    end

    def test_without_a_token_no_authorization_header_is_sent
      stub_request(:get, ADVISORY_URL).to_return(status: 200, body: fixture('advisories/GHSA-qccp-gfcp-xxvc.json'),
                                                 headers: json_header)

      GitHubClient.new(token: nil).advisory('GHSA-qccp-gfcp-xxvc')
      GitHubClient.new(token: '').advisory('GHSA-qccp-gfcp-xxvc')

      assert_requested(:get, ADVISORY_URL, times: 2) { |request| !request.headers.key?('Authorization') }
    end

    def test_open_issues_lists_labeled_open_issues
      query = { state: 'open', labels: 'sla-remediation', per_page: '100' }
      issues = [{ 'number' => 7, 'title' => 'urllib3', 'body' => 'body', 'html_url' => 'https://example/7' }]
      stub_request(:get, ISSUES_URL).with(query: query)
                                    .to_return(status: 200, body: issues.to_json, headers: json_header)

      result = @client.open_issues('kylesnowschwartz/superset', label: 'sla-remediation')

      assert_requested :get, ISSUES_URL, query: query, headers: HEADERS
      assert_equal 1, result.size
      assert_equal 7, result[0].number
      assert_equal 'urllib3', result[0].title
      assert_equal 'body', result[0].body
      assert_equal 'https://example/7', result[0].html_url
    end

    def test_create_issue_posts_title_body_and_labels
      created = { 'number' => 12, 'title' => 't', 'body' => 'b', 'html_url' => 'https://example/12' }
      stub_request(:post, ISSUES_URL).to_return(status: 201, body: created.to_json, headers: json_header)

      issue = @client.create_issue('kylesnowschwartz/superset', title: 't', body: 'b', labels: ['sla-remediation'])

      assert_requested :post, ISSUES_URL, headers: HEADERS,
                                          body: { title: 't', body: 'b', labels: ['sla-remediation'] }.to_json
      assert_equal 12, issue.number
      assert_equal 'https://example/12', issue.html_url
    end

    def test_create_issue_comment_posts_the_body_and_returns_the_comment_url
      created = { 'id' => 1, 'html_url' => 'https://example/issues/4#issuecomment-1' }
      stub_request(:post, "#{ISSUES_URL}/4/comments")
        .to_return(status: 201, body: created.to_json, headers: json_header)

      url = @client.create_issue_comment('kylesnowschwartz/superset', 4, 'PR opened')

      assert_requested :post, "#{ISSUES_URL}/4/comments", headers: HEADERS, body: { body: 'PR opened' }.to_json
      assert_equal 'https://example/issues/4#issuecomment-1', url
    end

    def test_issue_reads_one_issue
      item = JSON.parse(fixture('github_issues_opened.json')).fetch('issue')
      stub_request(:get, "#{ISSUES_URL}/4").to_return(status: 200, body: item.to_json, headers: json_header)

      issue = @client.issue('kylesnowschwartz/superset', 4)

      assert_requested :get, "#{ISSUES_URL}/4", headers: HEADERS
      assert_equal 4, issue.number
      assert_equal 'test: webhook path (throwaway)', issue.title
      assert_equal 'https://github.com/kylesnowschwartz/superset/issues/4', issue.html_url
      assert_includes issue.body, 'package: urllib3'
    end

    def test_open_pull_request_finds_the_open_pull_from_the_branch
      query = { state: 'open', head: 'kylesnowschwartz:fix/urllib3-sla-4' }
      pulls = [{ 'number' => 9, 'title' => 'fix: urllib3', 'html_url' => 'https://example/pull/9' }]
      stub_request(:get, PULLS_URL).with(query: query).to_return(status: 200, body: pulls.to_json, headers: json_header)

      pull = @client.open_pull_request('kylesnowschwartz/superset', head_branch: 'fix/urllib3-sla-4')

      assert_requested :get, PULLS_URL, query: query, headers: HEADERS
      assert_equal 9, pull.number
      assert_equal 'fix: urllib3', pull.title
      assert_equal 'https://example/pull/9', pull.html_url
    end

    def test_open_pull_request_is_nil_when_none_is_open
      stub_request(:get, PULLS_URL).with(query: hash_including(state: 'open'))
                                   .to_return(status: 200, body: '[]', headers: json_header)

      assert_nil @client.open_pull_request('kylesnowschwartz/superset', head_branch: 'fix/urllib3-sla-4')
    end

    def test_branch_exists_is_true_for_a_found_ref_and_false_when_not_found
      stub_request(:get, REF_URL).to_return({ status: 200, body: '{"ref":"refs/heads/fix/urllib3-sla-4"}',
                                              headers: json_header },
                                            { status: 404, body: '{"message":"Not Found"}', headers: json_header })

      assert @client.branch_exists?('kylesnowschwartz/superset', 'fix/urllib3-sla-4')
      refute @client.branch_exists?('kylesnowschwartz/superset', 'fix/urllib3-sla-4')
      assert_requested :get, REF_URL, times: 2, headers: HEADERS
    end

    def test_branch_exists_raises_on_other_errors
      stub_request(:get, REF_URL).to_return(status: 403, body: '{"message":"Forbidden"}', headers: json_header)

      error = assert_raises(GitHubAPIError) { @client.branch_exists?('kylesnowschwartz/superset', 'fix/urllib3-sla-4') }

      assert_equal 403, error.status
    end

    def test_open_pull_requests_lists_every_open_pull_with_its_head_branch
      query = { state: 'open', per_page: '100' }
      pulls = [{ 'number' => 9, 'title' => 'fix: urllib3', 'html_url' => 'https://example/pull/9',
                 'head' => { 'ref' => 'fix/urllib3-sla-4' } },
               { 'number' => 2, 'title' => 'chore', 'html_url' => 'https://example/pull/2',
                 'head' => { 'ref' => 'chore/unrelated' } }]
      stub_request(:get, PULLS_URL).with(query: query).to_return(status: 200, body: pulls.to_json, headers: json_header)

      result = @client.open_pull_requests('kylesnowschwartz/superset')

      assert_requested :get, PULLS_URL, query: query, headers: HEADERS
      assert_equal [9, 2], result.map(&:number)
      assert_equal ['fix/urllib3-sla-4', 'chore/unrelated'], result.map(&:head_branch)
      assert_equal 'https://example/pull/9', result[0].html_url
    end

    def test_close_pull_request_patches_the_state_to_closed
      closed = { 'number' => 9, 'title' => 'fix: urllib3', 'html_url' => 'https://example/pull/9', 'state' => 'closed',
                 'head' => { 'ref' => 'fix/urllib3-sla-4' } }
      stub_request(:patch, "#{PULLS_URL}/9").to_return(status: 200, body: closed.to_json, headers: json_header)

      pull = @client.close_pull_request('kylesnowschwartz/superset', 9)

      assert_requested :patch, "#{PULLS_URL}/9", headers: HEADERS, body: { state: 'closed' }.to_json
      assert_equal 9, pull.number
      assert_equal 'fix/urllib3-sla-4', pull.head_branch
    end

    def test_pull_request_status_is_success_when_every_run_completed_and_passed
      stub_request(:get, "#{PULLS_URL}/9")
        .to_return(status: 200, body: { number: 9, merged: false, mergeable: true,
                                        head: { sha: 'abc123' } }.to_json, headers: json_header)
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/commits/abc123/check-runs')
        .to_return(status: 200, body: { check_runs: [{ status: 'completed', conclusion: 'success' },
                                                     { status: 'completed', conclusion: 'neutral' },
                                                     { status: 'completed', conclusion: 'skipped' }] }.to_json,
                   headers: json_header)

      status = @client.pull_request_status('kylesnowschwartz/superset', 9)

      assert_equal 'abc123', status.head_sha
      assert_equal false, status.merged
      assert_equal true, status.mergeable
      assert_equal 'success', status.checks
    end

    def test_pull_request_status_is_pending_when_a_run_has_not_completed
      stub_request(:get, "#{PULLS_URL}/9")
        .to_return(status: 200, body: { number: 9, merged: false, mergeable: nil,
                                        head: { sha: 'abc123' } }.to_json, headers: json_header)
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/commits/abc123/check-runs')
        .to_return(status: 200, body: { check_runs: [{ status: 'in_progress', conclusion: nil }] }.to_json,
                   headers: json_header)

      assert_equal 'pending', @client.pull_request_status('kylesnowschwartz/superset', 9).checks
    end

    def test_pull_request_status_is_failure_when_a_completed_run_failed
      stub_request(:get, "#{PULLS_URL}/9")
        .to_return(status: 200, body: { number: 9, merged: false, mergeable: false,
                                        head: { sha: 'abc123' } }.to_json, headers: json_header)
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/commits/abc123/check-runs')
        .to_return(status: 200, body: { check_runs: [{ status: 'completed', conclusion: 'success' },
                                                     { status: 'completed', conclusion: 'failure' }] }.to_json,
                   headers: json_header)

      assert_equal 'failure', @client.pull_request_status('kylesnowschwartz/superset', 9).checks
    end

    def test_pull_request_status_is_none_when_there_are_no_check_runs
      stub_request(:get, "#{PULLS_URL}/9")
        .to_return(status: 200, body: { number: 9, merged: true, mergeable: nil,
                                        head: { sha: 'abc123' } }.to_json, headers: json_header)
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/commits/abc123/check-runs')
        .to_return(status: 200, body: { check_runs: [] }.to_json, headers: json_header)

      status = @client.pull_request_status('kylesnowschwartz/superset', 9)

      assert_equal 'none', status.checks
      assert_equal true, status.merged
    end

    def test_delete_branch_deletes_the_head_ref
      stub_request(:delete, REFS_URL).to_return(status: 204, body: '')

      assert_nil @client.delete_branch('kylesnowschwartz/superset', 'fix/urllib3-sla-4')
      assert_requested :delete, REFS_URL, headers: HEADERS
    end

    def test_close_issue_patches_the_state_to_closed
      closed = { 'number' => 4, 'title' => 'urllib3', 'body' => 'body', 'html_url' => 'https://example/4',
                 'state' => 'closed' }
      stub_request(:patch, "#{ISSUES_URL}/4").to_return(status: 200, body: closed.to_json, headers: json_header)

      issue = @client.close_issue('kylesnowschwartz/superset', 4)

      assert_requested :patch, "#{ISSUES_URL}/4", headers: HEADERS, body: { state: 'closed' }.to_json
      assert_equal 4, issue.number
      assert_equal 'https://example/4', issue.html_url
    end

    def test_file_with_sha_returns_the_decoded_text_and_the_blob_sha
      body = { 'encoding' => 'base64', 'sha' => 'abc123', 'content' => Base64.encode64("urllib3==2.7.0\n") }.to_json
      stub_request(:get, REQUIREMENTS_URL).with(query: { ref: 'master' })
                                          .to_return(status: 200, body: body, headers: json_header)

      file = @client.file_with_sha('kylesnowschwartz/superset', 'requirements/base.txt', ref: 'master')

      assert_requested :get, REQUIREMENTS_URL, query: { ref: 'master' }, headers: HEADERS
      assert_equal "urllib3==2.7.0\n", file.text
      assert_equal Encoding::UTF_8, file.text.encoding
      assert_equal 'abc123', file.sha
    end

    def test_update_file_puts_the_encoded_content_with_message_sha_and_branch
      created = { 'content' => { 'sha' => 'def456' }, 'commit' => { 'html_url' => 'https://example/commit/1' } }
      stub_request(:put, REQUIREMENTS_URL).to_return(status: 200, body: created.to_json, headers: json_header)

      url = @client.update_file('kylesnowschwartz/superset', 'requirements/base.txt',
                                content: "urllib3==2.4.0\n", message: 'chore: reseed', sha: 'abc123', branch: 'master')

      expected = { message: 'chore: reseed', content: Base64.strict_encode64("urllib3==2.4.0\n"), sha: 'abc123',
                   branch: 'master' }.to_json

      assert_requested :put, REQUIREMENTS_URL, headers: HEADERS, body: expected
      assert_equal 'https://example/commit/1', url
    end

    private

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end

    def json_header
      { 'Content-Type' => 'application/json' }
    end
  end
end
