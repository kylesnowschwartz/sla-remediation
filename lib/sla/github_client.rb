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

    Advisory = Struct.new(:ghsa_id, :cve_id, :severity, :summary, keyword_init: true)
    Issue = Struct.new(:number, :title, :body, :html_url, keyword_init: true)

    # Without a token the client is anonymous, which is enough for the public
    # advisories endpoint but not for reading or filing issues.
    def initialize(token: ENV.fetch('SLA_GITHUB_TOKEN', nil), connection: nil)
      @connection = connection || build_connection(token)
    end

    # Text of a file in the repository at the given ref. The contents API
    # base64-encodes the file body.
    def file_contents(repo, path, ref:)
      body = request(:get, "/repos/#{repo}/contents/#{path}", params: { ref: ref })
      encoding = body['encoding']
      raise Error, "GitHub returned #{encoding.inspect} encoding for #{repo}/#{path}" unless encoding == 'base64'

      Base64.decode64(body.fetch('content')).force_encoding(Encoding::UTF_8)
    end

    # A global security advisory from the GitHub Advisory Database.
    def advisory(ghsa_id)
      body = request(:get, "/advisories/#{ghsa_id}")
      Advisory.new(ghsa_id: body.fetch('ghsa_id'), cve_id: body['cve_id'],
                   severity: body.fetch('severity'), summary: body['summary'])
    end

    # Open issues carrying the label, first page of up to 100.
    def open_issues(repo, label:)
      params = { state: 'open', labels: label, per_page: ISSUES_PER_PAGE }
      request(:get, "/repos/#{repo}/issues", params: params).map { |item| build_issue(item) }
    end

    def create_issue(repo, title:, body:, labels:)
      build_issue(request(:post, "/repos/#{repo}/issues", payload: { title: title, body: body, labels: labels }))
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

    def request(method, path, params: nil, payload: nil)
      response = @connection.run_request(method, path, payload, nil) { |req| req.params.update(params) if params }
      raise GitHubAPIError.new(status: response.status, body: response.body) unless response.success?

      response.body
    rescue Faraday::Error => e
      raise Error, "GitHub API request failed: #{e.message}"
    end
  end
end
