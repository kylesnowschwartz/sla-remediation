# frozen_string_literal: true

require 'json'
require 'sequel'

require_relative 'remediation_prompt'

module SLA
  # Starts the one Devin session that remediates a recorded finding and records
  # it in the sessions table. A finding without a fix version is never dispatched,
  # and neither is one whose fix branch or pull request already exists on GitHub.
  #
  # The sessions row is inserted as a reservation before the Devin API is called,
  # so the unique index on finding_id decides which of two racing dispatches
  # spends ACUs; the loser never reaches Devin.
  class Dispatcher
    TAG = 'sla-remediation'
    RESERVED_STATUS = 'dispatching'

    def initialize(db:, devin:, github:, repo:, max_acu_limit: 3, out: $stdout)
      @db = db
      @devin = devin
      @github = github
      @repo = repo
      @max_acu_limit = max_acu_limit
      @out = out
    end

    # Returns :dispatched, :already_dispatched, :not_fixable, or :not_found.
    def dispatch(issue_number)
      finding = findings.first(issue_number: issue_number)
      return :not_found unless finding
      return :not_fixable if finding[:fix_version].nil?
      return :already_dispatched if dispatched?(finding) || remediation_exists?(finding)

      finding = with_issue_details(finding)
      session = create_session(finding, reserve(finding))
      @out.puts "dispatched issue ##{issue_number} → #{session.url}"
      :dispatched
    rescue Sequel::UniqueConstraintViolation
      :already_dispatched
    end

    # Prints the prompt and the create-session payload for a finding without
    # creating anything. Returns :previewed, :not_fixable, or :not_found.
    def preview(issue_number)
      finding = findings.first(issue_number: issue_number)
      return :not_found unless finding
      return :not_fixable if finding[:fix_version].nil?

      request = session_request(with_issue_details(finding))
      @out.puts request[:prompt]
      @out.puts JSON.pretty_generate(request)
      :previewed
    end

    # The keyword arguments passed to DevinClient#create_session for a findings row.
    def session_request(finding)
      {
        prompt: RemediationPrompt.render(finding, repo: @repo),
        title: finding[:issue_title],
        repos: [@repo],
        tags: [TAG, "issue-#{finding[:issue_number]}"],
        structured_output_schema: RemediationPrompt.schema,
        max_acu_limit: @max_acu_limit,
        resumable: true
      }
    end

    private

    # The branch the prompt tells the session to create.
    def fix_branch(finding)
      "fix/#{finding[:package]}-sla-#{finding[:issue_number]}"
    end

    def dispatched?(finding)
      !sessions.where(finding_id: finding[:id]).empty?
    end

    # Whether the fix branch or an open pull request from it is already on GitHub, and says which.
    def remediation_exists?(finding)
      branch = fix_branch(finding)
      if (pull = @github.open_pull_request(@repo, head_branch: branch))
        @out.puts "issue ##{finding[:issue_number]} already dispatched: open pull request #{pull.html_url}"
      elsif @github.branch_exists?(@repo, branch)
        @out.puts "issue ##{finding[:issue_number]} already dispatched: branch #{branch} exists in #{@repo}"
      else
        return false
      end
      true
    end

    # Findings recorded without the issue title and URL get them from GitHub, stored on the row.
    def with_issue_details(finding)
      return finding unless finding[:issue_title].nil? || finding[:issue_url].nil?

      issue = @github.issue(@repo, finding[:issue_number])
      details = { issue_title: issue.title, issue_url: issue.html_url }
      findings.where(id: finding[:id]).update(details)
      finding.merge(details)
    end

    def reserve(finding)
      sessions.insert(finding_id: finding[:id], status: RESERVED_STATUS, last_polled_at: Time.now.utc)
    end

    # Creates the Devin session and fills in the reserved row; the reservation is
    # released when the session cannot be created.
    def create_session(finding, reservation_id)
      session = begin
        @devin.create_session(**session_request(finding))
      rescue StandardError
        sessions.where(id: reservation_id).delete
        raise
      end
      sessions.where(id: reservation_id).update(devin_session_id: session.session_id, status: session.status,
                                                status_detail: session.status_detail, started_at: session.created_at)
      session
    end

    def findings
      @db[:findings]
    end

    def sessions
      @db[:sessions]
    end
  end
end
