# frozen_string_literal: true

require 'base64'
require 'faraday'

require_relative 'errors'

module SLA
  # HTTP client for the GitHub REST API. Every non-2xx response raises GitHubAPIError.
  class GitHubClient
    BASE_URL = 'https://api.github.com'
    API_VERSION = '2022-11-28'
    TIMEOUT_SECONDS = 15
    ISSUES_PER_PAGE = 100
    PULLS_PER_PAGE = 100

    CHECK_RUN_FAILURE_CONCLUSIONS = %w[failure timed_out cancelled action_required].freeze
    CHECK_RUN_SUCCESS_CONCLUSIONS = %w[success neutral skipped].freeze

    Advisory = Struct.new(:ghsa_id, :cve_id, :severity, :summary, keyword_init: true)
    Issue = Struct.new(:number, :title, :body, :html_url, keyword_init: true)
    PullRequest = Struct.new(:number, :title, :html_url, :head_branch, keyword_init: true)
    FileContents = Struct.new(:text, :sha, keyword_init: true)
    # `checks` is one of "pending" (a run is not yet completed), "failure" (a
    # completed run failed, timed out, was cancelled, or needs action),
    # "success" (every completed run succeeded, was neutral, or was skipped),
    # or "none" (the head commit has no check runs at all).
    PullRequestStatus = Struct.new(:head_sha, :mergeable, :merged, :checks, keyword_init: true)

    # Without a token the client is anonymous, which is enough for the public
    # advisories endpoint but not for reading or filing issues.
    def initialize(token: ENV.fetch('SLA_GITHUB_TOKEN', nil), connection: nil)
      @connection = connection || build_connection(token)
    end

    # Text of a file in the repository at the given ref. The contents API
    # base64-encodes the file body.
    def file_contents(repo, path, ref:)
      body = request(:get, "/repos/#{repo}/contents/#{path}", params: { ref: ref })
      decode_contents(body, repo, path)
    end

    # Text of a file at the given ref together with its blob sha, which the
    # contents API requires to update the file.
    def file_with_sha(repo, path, ref:)
      body = request(:get, "/repos/#{repo}/contents/#{path}", params: { ref: ref })
      FileContents.new(text: decode_contents(body, repo, path), sha: body.fetch('sha'))
    end

    # Replaces the file on the branch in one commit; `sha` is the blob sha of
    # the version being replaced. Returns the new commit's URL.
    def update_file(repo, path, content:, message:, sha:, branch:)
      payload = { message: message, content: Base64.strict_encode64(content), sha: sha, branch: branch }
      request(:put, "/repos/#{repo}/contents/#{path}", payload: payload).fetch('commit')['html_url']
    end

    # A global security advisory from the GitHub Advisory Database.
    def advisory(ghsa_id)
      body = request(:get, "/advisories/#{ghsa_id}")
      Advisory.new(ghsa_id: body.fetch('ghsa_id'), cve_id: body['cve_id'],
                   severity: body.fetch('severity'), summary: body['summary'])
    end

    def issue(repo, number)
      build_issue(request(:get, "/repos/#{repo}/issues/#{number}"))
    end

    # Open issues carrying the label, first page of up to 100.
    def open_issues(repo, label:)
      params = { state: 'open', labels: label, per_page: ISSUES_PER_PAGE }
      request(:get, "/repos/#{repo}/issues", params: params).map { |item| build_issue(item) }
    end

    def create_issue(repo, title:, body:, labels:)
      build_issue(request(:post, "/repos/#{repo}/issues", payload: { title: title, body: body, labels: labels }))
    end

    # Posts a comment on an issue and returns the comment's URL.
    def create_issue_comment(repo, number, body)
      request(:post, "/repos/#{repo}/issues/#{number}/comments", payload: { body: body })['html_url']
    end

    def close_issue(repo, number)
      build_issue(request(:patch, "/repos/#{repo}/issues/#{number}", payload: { state: 'closed' }))
    end

    # Every open pull request, first page of up to 100, with its head branch name.
    def open_pull_requests(repo)
      params = { state: 'open', per_page: PULLS_PER_PAGE }
      request(:get, "/repos/#{repo}/pulls", params: params).map { |item| build_pull_request(item) }
    end

    # Closes the pull request without merging it.
    def close_pull_request(repo, number)
      build_pull_request(request(:patch, "/repos/#{repo}/pulls/#{number}", payload: { state: 'closed' }))
    end

    # Deletes the branch; the refs endpoint answers 204 with no body.
    def delete_branch(repo, branch)
      request(:delete, "/repos/#{repo}/git/refs/heads/#{branch}")
      nil
    end

    # The open pull request whose head is the named branch of the repository
    # itself (not a fork), or nil when there is none.
    def open_pull_request(repo, head_branch:)
      owner = repo.split('/').first
      params = { state: 'open', head: "#{owner}:#{head_branch}" }
      item = request(:get, "/repos/#{repo}/pulls", params: params).first
      build_pull_request(item) if item
    end

    # The pull request's head sha, mergeable/merged state, and the combined
    # result of the check runs on that sha.
    def pull_request_status(repo, number)
      pull = request(:get, "/repos/#{repo}/pulls/#{number}")
      sha = pull.dig('head', 'sha')
      runs = request(:get, "/repos/#{repo}/commits/#{sha}/check-runs").fetch('check_runs')
      PullRequestStatus.new(head_sha: sha, mergeable: pull['mergeable'], merged: pull['merged'],
                            checks: check_state(runs))
    end

    # Whether the repository has a branch of that name; the ref endpoint answers 404 when it does not.
    def branch_exists?(repo, branch)
      request(:get, "/repos/#{repo}/git/ref/heads/#{branch}")
      true
    rescue GitHubAPIError => e
      raise unless e.status == 404

      false
    end

    private

    def build_connection(token)
      Faraday.new(url: BASE_URL, request: { timeout: TIMEOUT_SECONDS }) do |f|
        f.headers['Authorization'] = "Bearer #{token}" unless token.to_s.empty?
        f.headers['Accept'] = 'application/vnd.github+json'
        f.headers['X-GitHub-Api-Version'] = API_VERSION
        f.request :json
        f.response :json
      end
    end

    def build_issue(item)
      Issue.new(number: item.fetch('number'), title: item['title'], body: item['body'], html_url: item['html_url'])
    end

    def decode_contents(body, repo, path)
      encoding = body['encoding']
      raise Error, "GitHub returned #{encoding.inspect} encoding for #{repo}/#{path}" unless encoding == 'base64'

      Base64.decode64(body.fetch('content')).force_encoding(Encoding::UTF_8)
    end

    def build_pull_request(item)
      PullRequest.new(number: item.fetch('number'), title: item['title'], html_url: item['html_url'],
                      head_branch: item.dig('head', 'ref'))
    end

    # rubocop:disable Metrics/CyclomaticComplexity -- four states decided in order; splitting further would
    # scatter one decision table across more methods than it clarifies.
    def check_state(runs)
      return 'none' if runs.empty?
      return 'pending' if runs.any?(&method(:pending_run?))
      return 'failure' if runs.any?(&method(:failed_run?))

      runs.all?(&method(:passed_run?)) ? 'success' : 'failure'
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def pending_run?(run)
      run['status'] != 'completed'
    end

    def failed_run?(run)
      CHECK_RUN_FAILURE_CONCLUSIONS.include?(run['conclusion'])
    end

    def passed_run?(run)
      CHECK_RUN_SUCCESS_CONCLUSIONS.include?(run['conclusion'])
    end

    def request(method, path, params: nil, payload: nil)
      response = @connection.run_request(method, path, payload, nil) { |req| req.params.update(params) if params }
      raise GitHubAPIError.new(status: response.status, body: response.body) unless response.success?

      response.body
    rescue Faraday::Error => e
      raise Error, "GitHub API request failed: #{e.message}"
    end
  end
end
