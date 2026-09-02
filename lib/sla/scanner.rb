# frozen_string_literal: true

require 'erb'

require_relative 'audit_report'
require_relative 'errors'
require_relative 'finding'
require_relative 'finding_block'
require_relative 'pip_audit'

module SLA
  # Audits the target repo's pins and files one labeled issue per vulnerable
  # package that doesn't already have an open one.
  class Scanner
    LABEL = 'sla-remediation'
    REQUIREMENTS_PATH = 'requirements/base.txt'
    TEMPLATE_PATH = File.expand_path('../../templates/finding_issue.md.erb', __dir__)

    # With `check_open_issues: false` the scanner never reads the repo's issues,
    # so an anonymous dry run touches only the public advisories endpoint.
    def initialize(github:, policy:, repo:, ref:, audit_runner: PipAudit.method(:run), out: $stdout,
                   check_open_issues: true)
      @github = github
      @policy = policy
      @repo = repo
      @ref = ref
      @audit_runner = audit_runner
      @out = out
      @check_open_issues = check_open_issues
      @advisories = {}
    end

    # Audits the pins in the requirements text, resolving each vuln's GitHub
    # advisory, and returns one Finding per vulnerable package, sorted by name.
    def findings(requirements_text)
      report = AuditReport.parse(@audit_runner.call(requirements_text))
      report.vulnerable_packages.sort_by(&:name).filter_map do |package|
        pairs = package.vulns.filter_map { |vuln| vuln.ghsa_id && [vuln, advisory(vuln.ghsa_id)] }
        Finding.from_audit(package, advisories: pairs) unless pairs.empty?
      end
    end

    # Files an issue for every finding without one, or with `dry_run` prints
    # what would be filed. Returns the findings that were (or would be) filed.
    def run(requirements_text: nil, dry_run: false)
      requirements_text ||= @github.file_contents(@repo, REQUIREMENTS_PATH, ref: @ref)
      open_issue_numbers = open_issue_numbers_by_package

      findings(requirements_text).filter_map do |finding|
        if (number = open_issue_numbers[finding.package])
          @out.puts "skipped #{finding.package} (open issue ##{number})"
          next
        end

        dry_run ? preview(finding) : file(finding)
        finding
      end
    end

    # The issue body: prose about the pins and the SLA window, then the yaml finding block.
    def render_body(finding)
      template.result_with_hash(finding: finding, days: @policy.days_for(finding.severity))
    end

    private

    def advisory(ghsa_id)
      @advisories[ghsa_id] ||= @github.advisory(ghsa_id)
    end

    # Packages that already have an open labeled issue, keyed to the issue
    # number. Issues whose body has no readable finding block are ignored.
    def open_issue_numbers_by_package
      return {} unless @check_open_issues

      @github.open_issues(@repo, label: LABEL).each_with_object({}) do |issue, numbers|
        package = FindingBlock.parse(issue.body).package
        numbers[package] ||= issue.number
      rescue Error
        next
      end
    end

    def file(finding)
      issue = @github.create_issue(@repo, title: finding.issue_title, body: render_body(finding), labels: [LABEL])
      @out.puts "filed ##{issue.number} #{finding.issue_title}"
    end

    def preview(finding)
      @out.puts "would file #{finding.issue_title}"
      @out.puts render_body(finding)
      @out.puts
    end

    def template
      @template ||= ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    end
  end
end
