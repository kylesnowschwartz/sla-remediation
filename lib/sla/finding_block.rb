# frozen_string_literal: true

require_relative 'errors'
require_relative 'yaml_block'

module SLA
  # The yaml finding block carried in an issue body: what is vulnerable, how
  # bad it is, and where the finding came from.
  class FindingBlock
    REQUIRED = %w[package severity].freeze

    attr_reader :package, :pinned, :fix_version, :advisories, :severity, :source

    # Parses the first fenced yaml block in the issue body.
    def self.parse(issue_body)
      block = YAMLBlock.first(issue_body)
      raise Error, 'issue body has no yaml finding block' unless block.is_a?(Hash)

      missing = REQUIRED.select { |key| block[key].to_s.empty? }
      raise Error, "finding block is missing #{missing.join(' and ')}" unless missing.empty?

      new(block)
    end

    def initialize(attrs)
      @package = attrs['package'].to_s
      @pinned = version(attrs['pinned'])
      @fix_version = version(attrs['fix_version'])
      @advisories = Array(attrs['advisories']).map(&:to_s).freeze
      @severity = attrs['severity'].to_s.downcase
      @source = attrs['source']&.to_s
    end

    private

    def version(value)
      value&.to_s
    end
  end
end
