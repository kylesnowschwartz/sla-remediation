# frozen_string_literal: true

require 'base64'
require 'faraday'
require 'time'

require_relative 'errors'

module SLA
  # HTTP client for the GitHub REST API. Every non-2xx response raises GitHubAPIError.
  class GitHubClient
    BASE_URL = 'https://api.github.com'
    API_VERSION = '2022-11-28'
    TIMEOUT_SECONDS = 15
    ISSUES_PER_PAGE = 100
    PULLS_PER_PAGE = 100
    CHECK_RUNS_PER_PAGE = 100
    CHECK_RUN_OUTPUT_LINES = 40

    CHECK_RUN_FAILURE_CONCLUSIONS = %w[failure timed_out cancelled action_required].freeze
    CHECK_RUN_SUCCESS_CONCLUSIONS = %w[success neutral skipped].freeze

    Advisory = Struct.new(:ghsa_id, :cve_id, :severity, :summary, keyword_init: true)
    Issue = Struct.new(:number, :title, :body, :html_url, keyword_init: true)
    PullRequest = Struct.new(:number, :title, :html_url, :head_branch, keyword_init: true)
    FileContents = Struct.new(:text, :sha, keyword_init: true)
    # `state` is GitHub's "open" or "closed"; `merged_at` is the merge time or
    # nil. `checks` is one of "pending" (a run is not yet completed), "failure"
    # (a completed run failed, timed out, was cancelled, or needs action),
    # "success" (every completed run succeeded, was neutral, or was skipped),
    # or "none" (the head commit has no check runs at all). `checks_at` is when
    # the last run completed for "success" and "failure", and nil otherwise.
    # `check_runs` is every run on the head commit as GitHub returned it, so
    # the failed ones can be read (failed_check_runs) without a second fetch.
    # Only the Checks API is read, so commit statuses posted by CI systems
    # outside GitHub Actions are not seen.
    PullRequestStatus = Struct.new(:head_sha, :head_branch, :state, :mergeable, :merged, :merged_at, :checks,
                                   :checks_at, :check_runs, keyword_init: true)
    # One failed check run: its name, the page GitHub shows for it, and the
    # first CHECK_RUN_OUTPUT_LINES lines of its output summary (or text when
    # there is no summary), or nil when the run reported no output.
    FailedCheckRun = Struct.new(:name, :details_url, :output, keyword_init: true)

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

    # The pull request's head sha, open/closed and mergeable/merged state, and
    # the combined result of every check run on that sha.
    def pull_request_status(repo, number)
      pull = request(:get, "/repos/#{repo}/pulls/#{number}")
      sha = pull.dig('head', 'sha')
      runs = check_runs(repo, sha)
      checks = check_state(runs)
      PullRequestStatus.new(head_sha: sha, head_branch: pull.dig('head', 'ref'), state: pull['state'],
                            mergeable: pull['mergeable'], merged: pull['merged'],
                            merged_at: parse_time(pull['merged_at']),
                            checks: checks, checks_at: checks_completed_at(runs, checks), check_runs: runs)
    end

    # The runs among the status's check runs that failed, timed out, were
    # cancelled, or need action, with enough of each one's output to see what
    # went wrong. Job logs are not downloaded; the details URL leads to them.
    def failed_check_runs(status)
      status.check_runs.select(&method(:failed_run?)).map do |run|
        FailedCheckRun.new(name: run['name'], details_url: run['details_url'], output: check_run_output(run))
      end
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

    # Every check run on the commit. The endpoint pages at CHECK_RUNS_PER_PAGE
    # and reports the whole count, so pages are read until that many runs are in
    # hand (or a page comes back empty, should the count be off).
    def check_runs(repo, sha)
      path = "/repos/#{repo}/commits/#{sha}/check-runs"
      runs = []
      (1..).each do |page|
        body = request(:get, path, params: check_runs_params(page))
        batch = body.fetch('check_runs')
        runs.concat(batch)
        return runs if batch.empty? || runs.size >= body.fetch('total_count')
      end
    end

    def check_runs_params(page)
      params = { per_page: CHECK_RUNS_PER_PAGE }
      params[:page] = page if page > 1
      params
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

    def check_run_output(run)
      text = [run.dig('output', 'summary'), run.dig('output', 'text')].find { |value| !value.to_s.strip.empty? }
      text.lines.first(CHECK_RUN_OUTPUT_LINES).join.chomp if text
    end

    # When the last run finished, which is when the combined result was decided.
    def checks_completed_at(runs, checks)
      return nil unless %w[success failure].include?(checks)

      runs.filter_map { |run| parse_time(run['completed_at']) }.max
    end

    def parse_time(value)
      Time.iso8601(value).utc if value
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
