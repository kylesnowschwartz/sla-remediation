# frozen_string_literal: true

require 'json'

require_relative 'errors'

module SLA
  # The JSON report written by `pip-audit --format json`: every dependency
  # with the known vulnerabilities in its pinned version.
  class AuditReport
    GHSA_PREFIX = 'GHSA-'

    # One vulnerability reported for a package.
    class Vuln
      attr_reader :id, :fix_versions, :aliases

      def initialize(attrs)
        @id = attrs.fetch('id')
        @fix_versions = Array(attrs['fix_versions']).map(&:to_s).freeze
        @aliases = Array(attrs['aliases']).map(&:to_s).freeze
      end

      # The GitHub advisory id: the vuln's own id when it is one, otherwise
      # the first among the aliases, or nil when the advisory has none.
      def ghsa_id
        [id, *aliases].find { |name| name.start_with?(GHSA_PREFIX) }
      end
    end

    # A dependency and the vulnerabilities found in its pinned version.
    class Package
      attr_reader :name, :version, :vulns

      def initialize(attrs)
        @name = attrs.fetch('name')
        @version = attrs.fetch('version').to_s
        @vulns = Array(attrs['vulns']).map { |vuln| Vuln.new(vuln) }.freeze
      end

      def vulnerable?
        !vulns.empty?
      end
    end

    attr_reader :packages

    def self.parse(json_text)
      report = JSON.parse(json_text)
      raise Error, 'pip-audit report has no dependencies list' unless report.is_a?(Hash) && report['dependencies']

      new(report.fetch('dependencies').map { |dep| Package.new(dep) })
    rescue JSON::ParserError => e
      raise Error, "pip-audit report is not valid JSON: #{e.message}"
    end

    def initialize(packages)
      @packages = packages.freeze
    end

    def vulnerable_packages
      packages.select(&:vulnerable?)
    end
  end
end
