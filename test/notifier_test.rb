# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class NotifierTest < Minitest::Test
    REPO = 'kylesnowschwartz/superset'
    COMMENTS_URL = "https://api.github.com/repos/#{REPO}/issues/8/comments".freeze
    PR_URL = "https://github.com/#{REPO}/pull/9".freeze
    SESSION_ID = '812ce7c3f89f4e88bce68dc03c9dd462'
    JSON_HEADER = { 'Content-Type' => 'application/json' }.freeze

    def setup
      @notifier = Notifier::IssueComment.new(github: GitHubClient.new(token: 'test-token'), repo: REPO)
      stub_request(:post, COMMENTS_URL).to_return(status: 201, body: '{"html_url":"https://example/comment/1"}',
                                                  headers: JSON_HEADER)
    end

    def test_issue_comment_posts_the_links_and_inside_the_window
      result = @notifier.pr_opened(finding(due_at: Time.now.utc + 3600), session)

      assert_equal 'https://example/comment/1', result
      assert_requested(:post, COMMENTS_URL, headers: { 'Authorization' => 'Bearer test-token' }) do |req|
        body = JSON.parse(req.body).fetch('body')
        lines = body.split("\n")

        assert_equal 3, lines.size
        assert_equal "Pull request: #{PR_URL}", lines[0]
        assert_equal "Devin session: https://app.devin.ai/sessions/#{SESSION_ID}", lines[1]
        assert_match(/\ADue \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC, inside the SLA window\.\z/, lines[2])
        true
      end
    end

    def test_issue_comment_says_past_the_window_after_the_due_date
      @notifier.pr_opened(finding(due_at: Time.utc(2026, 9, 1, 8, 25)), session)

      assert_requested(:post, COMMENTS_URL) do |req|
        assert_match(/\nDue 2026-09-01 08:25 UTC, past the SLA window\.\z/, JSON.parse(req.body).fetch('body'))
        true
      end
    end

    def test_null_posts_nothing
      assert_nil Notifier::Null.new.pr_opened(finding(due_at: Time.now.utc), session)
      assert_not_requested :post, COMMENTS_URL
    end

    private

    def finding(due_at:)
      { id: 1, issue_number: 8, package: 'urllib3', due_at: due_at }
    end

    def session
      { id: 1, finding_id: 1, devin_session_id: SESSION_ID, pr_url: PR_URL, pr_state: 'open' }
    end
  end
end
