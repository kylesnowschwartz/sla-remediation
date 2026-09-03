# frozen_string_literal: true

require 'erb'

module SLA
  # The message the tracker sends a remediation session when the checks on
  # its pull request are red, rendered from the markdown template with the
  # pull request, the failing commit, and the failed check runs as
  # GitHubClient#failed_check_runs returns them.
  class RepairPrompt
    TEMPLATE_PATH = File.expand_path('../../prompts/repair_ci.md.erb', __dir__)

    def self.render(pr_url:, branch:, sha:, failures:)
      template.result_with_hash(pr_url: pr_url, branch: branch, sha: sha, failures: failures)
    end

    def self.template
      @template ||= ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    end

    private_class_method :template
  end
end
