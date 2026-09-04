# frozen_string_literal: true

require 'faraday'
require 'uri'

require_relative 'errors'
require_relative 'devin_client/session'

module SLA
  # HTTP client for the Devin API v3. All calls are scoped to one organization
  # and every non-2xx response raises DevinAPIError.
  class DevinClient
    BASE_URL = 'https://api.devin.ai'
    TIMEOUT_SECONDS = 15

    Repository = Struct.new(:repo_path, :repo_name, :git_connection_host, keyword_init: true)
    Message = Struct.new(:source, :origin, :message, :created_at, keyword_init: true)
    Playbook = Struct.new(:playbook_id, :title, :body, :macro, :structured_output_schema, keyword_init: true)

    def initialize(api_key: ENV.fetch('DEVIN_SERVICE_API_KEY_V3'), org_id: ENV.fetch('DEVIN_ORG_ID'), connection: nil)
      @org_id = org_id
      @connection = connection || build_connection(api_key)
    end

    # Repositories live under the v3beta1 prefix; the v3 path returns 404.
    def list_repositories
      body = request(:get, "/v3beta1/organizations/#{@org_id}/repositories")
      body.fetch('items').map do |item|
        Repository.new(repo_path: item['repo_path'], repo_name: item['repo_name'],
                       git_connection_host: item['git_connection_host'])
      end
    end

    # Every organization playbook, following the cursor across pages.
    def list_playbooks
      items = []
      after = nil
      loop do
        body = request(:get, after ? "#{playbooks_path}?#{URI.encode_www_form(after: after)}" : playbooks_path)
        items.concat(body.fetch('items').map { |item| playbook_struct(item) })
        after = body['end_cursor']
        break unless body['has_next_page'] && after
      end
      items
    end

    def create_playbook(title:, body:, macro:, structured_output_schema:)
      payload = { title: title, body: body, macro: macro, structured_output_schema: structured_output_schema }
      playbook_struct(request(:post, playbooks_path, payload))
    end

    # Sends every field the create call sends; the API updates with PUT.
    def update_playbook(playbook_id, title:, body:, macro:, structured_output_schema:)
      payload = { title: title, body: body, macro: macro, structured_output_schema: structured_output_schema }
      playbook_struct(request(:put, playbooks_path(playbook_id), payload))
    end

    # A nil playbook_id is left out of the payload, so the session gets no playbook.
    def create_session(prompt:, title:, repos:, tags:, structured_output_schema:, max_acu_limit:, resumable: false,
                       playbook_id: nil)
      payload = {
        prompt: prompt, title: title, repos: repos, tags: tags, resumable: resumable,
        max_acu_limit: max_acu_limit, structured_output_schema: structured_output_schema
      }
      payload[:playbook_id] = playbook_id unless playbook_id.nil?
      Session.new(request(:post, sessions_path, payload))
    end

    def session(session_id)
      Session.new(request(:get, sessions_path(session_id)))
    end

    def messages(session_id)
      body = request(:get, "#{sessions_path(session_id)}/messages")
      body.fetch('items').map do |item|
        Message.new(source: item['source'], origin: item['origin'], message: item['message'],
                    created_at: unix_time(item['created_at']))
      end
    end

    def send_message(session_id, text)
      request(:post, "#{sessions_path(session_id)}/messages", { message: text })
    end

    private

    def build_connection(api_key)
      Faraday.new(url: BASE_URL, request: { timeout: TIMEOUT_SECONDS }) do |f|
        f.headers['Authorization'] = "Bearer #{api_key}"
        f.headers['Accept'] = 'application/json'
        f.request :json
        f.response :json
      end
    end

    def unix_time(seconds)
      Time.at(seconds).utc unless seconds.nil?
    end

    def playbook_struct(item)
      Playbook.new(playbook_id: item['playbook_id'], title: item['title'], body: item['body'], macro: item['macro'],
                   structured_output_schema: item['structured_output_schema'])
    end

    def sessions_path(session_id = nil)
      path = "/v3/organizations/#{@org_id}/sessions"
      session_id ? "#{path}/#{session_id}" : path
    end

    def playbooks_path(playbook_id = nil)
      path = "/v3/organizations/#{@org_id}/playbooks"
      playbook_id ? "#{path}/#{playbook_id}" : path
    end

    def request(method, path, payload = nil)
      response = @connection.run_request(method, path, payload, nil)
      raise DevinAPIError.new(status: response.status, body: response.body) unless response.success?

      response.body
    rescue Faraday::Error => e
      raise Error, "Devin API request failed: #{e.message}"
    end
  end
end
