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

    private

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end

    def json_header
      { 'Content-Type' => 'application/json' }
    end
  end
end
