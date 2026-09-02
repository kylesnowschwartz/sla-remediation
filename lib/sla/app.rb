# frozen_string_literal: true

require 'json'
require 'logger'
require 'sinatra/base'

require_relative 'db'
require_relative 'devin_client'
require_relative 'dispatcher'
require_relative 'errors'
require_relative 'github_client'
require_relative 'policy'
require_relative 'webhook'

module SLA
  class App < Sinatra::Base
    set :root, File.expand_path('../..', __dir__)
    set :views, File.join(root, 'views')

    # SECURITY-SLA.md of the target repo, fetched on first use and kept for the process lifetime.
    set :policy, -> { @policy ||= Policy.fetch(GitHubClient.new, repo: ENV.fetch('SLA_REPO')) }
    set :delivery_log, Logger.new($stdout)
    # Devin client and dispatcher output, created on first use; only used when SLA_AUTO_DISPATCH is "true".
    set :devin, -> { @devin ||= DevinClient.new }
    set :dispatch_out, $stdout

    get '/healthz' do
      content_type :json
      JSON.generate(ok: true)
    end

    post '/webhooks/github' do
      raw_body = request.body.read
      halt 401 unless Webhook::Signature.valid?(ENV.fetch('SLA_WEBHOOK_SECRET'), raw_body,
                                                request.env['HTTP_X_HUB_SIGNATURE_256'])

      content_type :json
      event = request.env['HTTP_X_GITHUB_EVENT']
      halt 200, JSON.generate(ok: true) if event == 'ping'

      payload = parse_json(raw_body)
      result = handle_delivery(event, payload)
      halt 204 if result == :ignored

      JSON.generate(result: result)
    end

    private

    def parse_json(raw_body)
      JSON.parse(raw_body)
    rescue JSON::ParserError => e
      halt 400, JSON.generate(error: "invalid JSON body: #{e.message}")
    end

    def handle_delivery(event, payload)
      handler = Webhook::Handler.new(db: DB, policy: settings.policy)
      result = handler.call(event, payload)
      dispatch = auto_dispatch(payload.dig('issue', 'number')) if result == :started
      log_delivery(event, payload, result, dispatch)
      result
    rescue SLA::Error => e
      log_delivery(event, payload, "error (#{e.message})")
      halt 422, JSON.generate(error: e.message)
    end

    def auto_dispatch(issue_number)
      return :off unless ENV['SLA_AUTO_DISPATCH'] == 'true'

      Dispatcher.new(db: DB, devin: settings.devin, repo: ENV.fetch('SLA_REPO'), out: settings.dispatch_out)
                .dispatch(issue_number)
    rescue SLA::Error => e
      "error (#{e.message})"
    end

    def log_delivery(event, payload, result, dispatch = nil)
      fields = { event: event, action: payload['action'], issue: payload.dig('issue', 'number'), result: result }
      fields[:dispatch] = dispatch if dispatch
      settings.delivery_log.info("webhook #{fields.map { |key, value| "#{key}=#{value}" }.join(' ')}")
    end
  end
end
