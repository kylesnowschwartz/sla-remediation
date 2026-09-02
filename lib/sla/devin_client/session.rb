# frozen_string_literal: true

require 'json'

module SLA
  class DevinClient
    # A Devin session as returned by the sessions endpoints.
    class Session
      PullRequest = Struct.new(:pr_url, :pr_state, keyword_init: true)

      STOPPED_STATUSES = %w[exit error].freeze
      STOPPED_DETAILS = %w[waiting_for_user finished inactivity].freeze

      attr_reader :session_id, :url, :status, :status_detail, :acus_consumed, :tags,
                  :pull_requests, :created_at, :updated_at, :structured_output

      def initialize(attrs)
        @session_id, @url, @status, @status_detail, @acus_consumed =
          attrs.values_at('session_id', 'url', 'status', 'status_detail', 'acus_consumed')
        @tags = Array(attrs['tags'])
        @pull_requests = build_pull_requests(attrs['pull_requests'])
        @created_at = unix_time(attrs['created_at'])
        @updated_at = unix_time(attrs['updated_at'])
        @structured_output = normalise_structured_output(attrs['structured_output'])
      end

      # The session is no longer working, whether it finished or Devin stopped it.
      def stopped?
        STOPPED_STATUSES.include?(status) || STOPPED_DETAILS.include?(status_detail)
      end

      # The session has produced something to act on: structured output or a pull request.
      def reported?
        !structured_output.nil? || !pull_requests.empty?
      end

      def settled?
        stopped? && reported?
      end

      def stalled?
        stopped? && !reported?
      end

      private

      def build_pull_requests(items)
        Array(items).map { |pr| PullRequest.new(pr_url: pr['pr_url'], pr_state: pr['pr_state']) }
      end

      def unix_time(seconds)
        Time.at(seconds).utc unless seconds.nil?
      end

      # The API sends a JSON object when the session had a schema and the JSON
      # string "null" when it did not; both collapse to a Hash or nil.
      def normalise_structured_output(value)
        case value
        when Hash then value
        when String then JSON.parse(value)
        end
      end
    end
  end
end
