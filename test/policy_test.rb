# frozen_string_literal: true

require 'base64'

require_relative 'test_helper'

module SLA
  class PolicyTest < Minitest::Test
    FIXTURES = File.expand_path('fixtures/github', __dir__)

    def setup
      @policy = Policy.load(security_sla_text)
    end

    def test_load_reads_sla_days_from_the_yaml_block
      assert_equal({ 'critical' => 2, 'high' => 2, 'medium' => 14, 'low' => 30 }, @policy.sla_days)
      assert_equal 14, @policy.days_for('medium')
    end

    def test_days_for_is_case_insensitive
      assert_equal 30, @policy.days_for('LOW')
    end

    def test_due_at_adds_the_window_in_days
      opened_at = Time.utc(2026, 9, 2, 8, 25, 30)

      assert_equal opened_at + (48 * 60 * 60), @policy.due_at('high', opened_at)
      assert_equal Time.utc(2026, 10, 2, 8, 25, 30), @policy.due_at('low', opened_at)
    end

    def test_unknown_severity_raises
      error = assert_raises(SLA::Error) { @policy.days_for('moderate') }

      assert_match(/unknown severity "moderate"/, error.message)
    end

    def test_document_without_a_yaml_block_raises
      assert_raises(SLA::Error) { Policy.load("# Security SLA\n\nNo block here.\n") }
    end

    def test_block_without_sla_days_raises
      assert_raises(SLA::Error) { Policy.load("```yaml\nwindows:\n  high: 2\n```\n") }
    end

    def test_missing_or_non_integer_window_raises
      assert_raises(SLA::Error) { Policy.load("```yaml\nsla_days:\n  critical: 2\n  high: 2\n  medium: 14\n```\n") }
      assert_raises(SLA::Error) do
        Policy.load("```yaml\nsla_days:\n  critical: two\n  high: 2\n  medium: 14\n  low: 30\n```\n")
      end
    end

    def test_fetch_loads_security_sla_from_the_repo_root
      url = 'https://api.github.com/repos/kylesnowschwartz/superset/contents/SECURITY-SLA.md'
      body = File.read(File.join(FIXTURES, 'github_contents_security_sla.json'))
      stub_request(:get, url).with(query: { ref: 'master' })
                             .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

      policy = Policy.fetch(GitHubClient.new(token: 'test-token'), repo: 'kylesnowschwartz/superset')

      assert_requested :get, url, query: { ref: 'master' }
      assert_equal 2, policy.days_for('critical')
    end

    private

    def security_sla_text
      contents = JSON.parse(File.read(File.join(FIXTURES, 'github_contents_security_sla.json')))
      Base64.decode64(contents['content'])
    end
  end
end
