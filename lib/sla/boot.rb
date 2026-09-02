# frozen_string_literal: true

require 'logger'

require_relative 'db'
require_relative 'devin_client'
require_relative 'github_client'
require_relative 'notifier'
require_relative 'tracker'

module SLA
  # Starts the tracker in a background thread beside the web server and stops
  # it when the process exits.
  module Boot
    DEVIN_ENV = %w[DEVIN_SERVICE_API_KEY_V3 DEVIN_ORG_ID].freeze
    JOIN_TIMEOUT_SECONDS = 5

    # Returns the tracker thread, or nil when SLA_TRACKER is "off" or the Devin
    # credentials are missing. Comments on issues only when SLA_GITHUB_TOKEN is
    # set. Each round is logged only when its summary differs from the last or
    # it settled, stalled, notified, or failed anything.
    def self.start_tracker(env: ENV, log: Logger.new($stdout))
      return if env['SLA_TRACKER'] == 'off' || !devin_configured?(env, log)

      tracker = Tracker.new(db: DB, devin: DevinClient.new, notifier: notifier(env), log: log)
      stop = Queue.new
      thread = Thread.new { run(tracker, stop, log) }
      at_exit do
        stop << :stop
        thread.join(JOIN_TIMEOUT_SECONDS)
      end
      thread
    end

    # IssueComment when SLA_GITHUB_TOKEN is set, Null otherwise.
    def self.notifier(env = ENV)
      return Notifier::Null.new if env['SLA_GITHUB_TOKEN'].to_s.empty?

      Notifier::IssueComment.new(github: GitHubClient.new(token: env['SLA_GITHUB_TOKEN']), repo: env.fetch('SLA_REPO'))
    end

    def self.devin_configured?(env, log)
      missing = DEVIN_ENV.select { |name| env[name].to_s.empty? }
      log.warn("tracker not started: missing #{missing.join(', ')}") unless missing.empty?
      missing.empty?
    end

    def self.run(tracker, stop, log)
      previous = nil
      tracker.run(stop: stop) do |summary|
        changed = summary != previous || summary.except(:polled).values.any?(&:positive?)
        log.info("tracker #{Tracker.summary_line(summary)}") if changed
        previous = summary
      end
    rescue StandardError => e
      log.error("tracker stopped: #{e.class}: #{e.message}")
    end

    private_class_method :devin_configured?, :run
  end
end
