# frozen_string_literal: true

require_relative 'errors'
require_relative 'yaml_block'

module SLA
  # Remediation windows per severity, read from a target repo's SECURITY-SLA.md.
  class Policy
    FILE_PATH = 'SECURITY-SLA.md'
    SEVERITIES = %w[critical high medium low].freeze
    SECONDS_PER_DAY = 24 * 60 * 60

    attr_reader :sla_days

    # Parses the markdown document and reads `sla_days` from its yaml block.
    def self.load(text)
      block = YAMLBlock.first(text)
      raise Error, "#{FILE_PATH} has no yaml block" unless block.is_a?(Hash)

      days = block['sla_days']
      raise Error, "#{FILE_PATH} yaml block has no sla_days" unless days.is_a?(Hash)

      new(days)
    end

    # Loads SECURITY-SLA.md from the root of the target repo.
    def self.fetch(github_client, repo:, ref: 'master')
      load(github_client.file_contents(repo, FILE_PATH, ref: ref))
    end

    def initialize(sla_days)
      @sla_days = SEVERITIES.each_with_object({}) do |severity, days|
        value = sla_days[severity]
        raise Error, "sla_days.#{severity} must be whole days, got #{value.inspect}" unless value.is_a?(Integer)

        days[severity] = value
      end.freeze
    end

    def days_for(severity)
      @sla_days.fetch(severity.to_s.downcase) do
        raise Error, "unknown severity #{severity.inspect}; expected one of #{SEVERITIES.join(', ')}"
      end
    end

    def due_at(severity, opened_at)
      opened_at + (days_for(severity) * SECONDS_PER_DAY)
    end
  end
end
