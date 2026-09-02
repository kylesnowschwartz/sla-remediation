# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class GitHubClientTest < Minitest::Test
    TOKEN = 'test-token'
    FIXTURES = File.expand_path('fixtures/github', __dir__)
    CONTENTS_URL = 'https://api.github.com/repos/kylesnowschwartz/superset/contents/SECURITY-SLA.md'
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

    private

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end

    def json_header
      { 'Content-Type' => 'application/json' }
    end
  end
end
