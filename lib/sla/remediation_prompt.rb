# frozen_string_literal: true

require 'erb'
require 'json'

module SLA
  # The prompt a remediation session is given, rendered from the markdown
  # template for one findings row, and the schema its structured output follows.
  class RemediationPrompt
    TEMPLATE_PATH = File.expand_path('../../prompts/remediate_dependency.md.erb', __dir__)
    SCHEMA_PATH = File.expand_path('../../schemas/remediation_result.json', __dir__)
    DUE_AT_FORMAT = '%Y-%m-%d %H:%M UTC'

    Finding = Struct.new(:package, :pinned, :fix_version, :advisories, :severity, keyword_init: true) do
      # Whether the fix crosses a major version boundary, comparing the
      # leading integer of the pinned and fix versions.
      def major_version_bump?
        pinned[/\A\d+/].to_i != fix_version[/\A\d+/].to_i
      end
    end
    Issue = Struct.new(:number, :title, :url, keyword_init: true)

    def self.render(finding_row, repo:)
      template.result_with_hash(finding: finding(finding_row), issue: issue(finding_row), repo: repo,
                                due_at: finding_row.fetch(:due_at).getutc.strftime(DUE_AT_FORMAT))
    end

    # The parsed structured output schema, read once per process.
    def self.schema
      @schema ||= JSON.parse(File.read(SCHEMA_PATH))
    end

    def self.template
      @template ||= ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    end

    def self.finding(row)
      Finding.new(package: row[:package], pinned: row[:pinned], fix_version: row[:fix_version],
                  advisories: JSON.parse(row[:advisories] || '[]'), severity: row[:severity])
    end

    def self.issue(row)
      Issue.new(number: row[:issue_number], title: row[:issue_title], url: row[:issue_url])
    end

    private_class_method :template, :finding, :issue
  end
end
