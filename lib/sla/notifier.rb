# frozen_string_literal: true

module SLA
  # Where notifications about a finding's remediation go. Every implementation
  # answers pr_opened(finding_row, session_row), called once per session when
  # its pull request is first seen.
  module Notifier
    SESSION_URL = 'https://app.devin.ai/sessions'
    DUE_AT_FORMAT = '%Y-%m-%d %H:%M UTC'

    # Comments on the finding's GitHub issue with the pull request link, the
    # Devin session link, and whether the due date has passed.
    class IssueComment
      def initialize(github:, repo:)
        @github = github
        @repo = repo
      end

      def pr_opened(finding_row, session_row)
        @github.create_issue_comment(@repo, finding_row.fetch(:issue_number), body(finding_row, session_row))
      end

      private

      def body(finding_row, session_row)
        due_at = finding_row.fetch(:due_at).getutc
        window = Time.now.utc <= due_at ? 'inside the SLA window' : 'past the SLA window'
        [
          "Pull request: #{session_row.fetch(:pr_url)}",
          "Devin session: #{SESSION_URL}/#{session_row.fetch(:devin_session_id)}",
          "Due #{due_at.strftime(DUE_AT_FORMAT)}, #{window}."
        ].join("\n")
      end
    end

    # Notifies nobody.
    class Null
      def pr_opened(_finding_row, _session_row); end
    end
  end
end
