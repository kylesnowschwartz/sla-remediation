# frozen_string_literal: true

require 'rubygems'

require_relative 'errors'

module SLA
  # One vulnerable package as the scanner sees it: the pinned version, the
  # release that fixes every advisory, and the worst severity among them.
  class Finding
    SOURCE = 'pip-audit'
    SEVERITIES = %w[low medium high critical].freeze
    # Used when no advisory carries a rating (GitHub reports those as "unknown").
    DEFAULT_SEVERITY = 'low'

    attr_reader :package, :pinned, :fix_version, :advisories, :severity, :source, :advisory_summaries, :cve_ids

    # Builds the finding for an audited package from `[vuln, advisory]` pairs:
    # each pip-audit vuln with the GitHub advisory it aliases.
    def self.from_audit(package, advisories:)
      raise Error, "#{package.name} has no advisories" if advisories.empty?

      github_advisories = advisories.map(&:last)
      severity = highest_severity(github_advisories)
      new(package: package.name, pinned: package.version,
          fix_version: highest_fix_version(advisories.map(&:first)),
          advisories: github_advisories.map(&:ghsa_id),
          severity: severity || DEFAULT_SEVERITY, severity_rated: !severity.nil?,
          advisory_summaries: index_by_ghsa(github_advisories, &:summary),
          cve_ids: index_by_ghsa(github_advisories, &:cve_id))
    end

    def self.highest_fix_version(vulns)
      vulns.flat_map(&:fix_versions).max_by { |version| Gem::Version.new(version) }
    end

    # The highest rated severity, or nil when every advisory is unrated.
    def self.highest_severity(github_advisories)
      rated = github_advisories.map { |advisory| advisory.severity.to_s.downcase } & SEVERITIES
      rated.max_by { |severity| SEVERITIES.index(severity) }
    end

    def self.index_by_ghsa(github_advisories)
      github_advisories.to_h { |advisory| [advisory.ghsa_id, yield(advisory)] }
    end

    def initialize(package:, pinned:, fix_version:, advisories:, severity:, severity_rated: true,
                   advisory_summaries: {}, cve_ids: {})
      @package = package
      @pinned = pinned
      @fix_version = fix_version
      @advisories = advisories.freeze
      @severity = severity
      @severity_rated = severity_rated
      @source = SOURCE
      @advisory_summaries = advisory_summaries.freeze
      @cve_ids = cve_ids.freeze
    end

    def fixable?
      !fix_version.nil?
    end

    # False when the severity is the default because no advisory carries a rating.
    def severity_rated?
      @severity_rated
    end

    # `[SLA high] urllib3 2.4.0 → 2.7.0`, or `: no fixed release` when nothing fixes it.
    def issue_title
      fix = fixable? ? " → #{fix_version}" : ': no fixed release'
      "[SLA #{severity}] #{package} #{pinned}#{fix}"
    end
  end
end
