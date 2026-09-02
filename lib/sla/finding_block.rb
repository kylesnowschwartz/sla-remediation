# frozen_string_literal: true

require_relative 'errors'
require_relative 'yaml_block'

module SLA
  # The yaml finding block carried in an issue body: what is vulnerable, how
  # bad it is, and where the finding came from.
  class FindingBlock
    REQUIRED = %w[package severity].freeze
    DEFAULT_ECOSYSTEM = 'pypi'

    attr_reader :package, :pinned, :fix_version, :advisories, :severity, :source, :ecosystem

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
      @severity = attrs['severity'].to_s.downcase
      @advisories = Array(attrs['advisories']).map(&:to_s).freeze
      @pinned, @fix_version, @source, @ecosystem = optional_text(attrs, 'pinned', 'fix_version', 'source', 'ecosystem')
      @ecosystem ||= DEFAULT_ECOSYSTEM
    end

    private

    # The named keys as strings, nil where the block leaves them out.
    def optional_text(attrs, *keys)
      keys.map { |key| attrs[key]&.to_s }
    end
  end
end
