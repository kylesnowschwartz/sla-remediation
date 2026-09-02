# frozen_string_literal: true

require 'json'
require 'openssl'
require 'time'
require 'rack/utils'
require 'sequel'

require_relative 'errors'
require_relative 'finding_block'

module SLA
  module Webhook
    LABEL = 'sla-remediation'

    # GitHub's X-Hub-Signature-256 header: "sha256=" + HMAC-SHA256(secret, body).
    module Signature
      PREFIX = 'sha256='

      def self.compute(secret, raw_body)
        PREFIX + OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
      end

      def self.valid?(secret, raw_body, header)
        return false if header.to_s.empty?

        Rack::Utils.secure_compare(compute(secret, raw_body), header)
      end
    end

    # Turns a verified `issues` delivery into a change to the findings table.
    class Handler
      def initialize(db:, policy:)
        @db = db
        @policy = policy
      end

      # Returns :started, :duplicate, :remediated, or :ignored.
      def call(event, payload)
        return :ignored unless event == 'issues'

        issue = payload.fetch('issue')
        case payload['action']
        when 'opened', 'labeled'
          starts_remediation?(payload) ? start(issue) : :ignored
        when 'closed'
          remediate(issue)
        else
          :ignored
        end
      end

      private

      def starts_remediation?(payload)
        case payload['action']
        when 'opened' then payload.fetch('issue').fetch('labels', []).any? { |label| label['name'] == LABEL }
        when 'labeled' then payload.dig('label', 'name') == LABEL
        else false
        end
      end

      def start(issue)
        finding = FindingBlock.parse(issue['body'])
        opened_at = Time.iso8601(issue.fetch('created_at'))
        due_at = @policy.due_at(finding.severity, opened_at)

        findings.insert(finding_row(finding, opened_at).merge(issue_number: issue.fetch('number'), due_at: due_at))
        :started
      rescue Sequel::UniqueConstraintViolation
        :duplicate
      end

      def finding_row(finding, opened_at)
        {
          package: finding.package, pinned: finding.pinned, fix_version: finding.fix_version,
          severity: finding.severity, source: finding.source, advisories: JSON.generate(finding.advisories),
          opened_at: opened_at, created_at: Time.now.utc
        }
      end

      def remediate(issue)
        closed_at = Time.iso8601(issue.fetch('closed_at'))
        updated = findings.where(issue_number: issue.fetch('number')).update(closed_at: closed_at)
        updated.positive? ? :remediated : :ignored
      end

      def findings
        @db[:findings]
      end
    end
  end
end
