# frozen_string_literal: true

module SLA
  # Undoes one run of the demo so the pipeline can start again from a clean
  # fork and an empty database: closes Devin's fix pull requests and deletes
  # their branches, closes the scan issues, puts the seeded vulnerable pins
  # back, and empties the sessions and findings tables.
  #
  # With `dry_run: true` only the reads happen and every line says "would".
  class DemoReset
    LABEL = 'sla-remediation'
    FIX_BRANCH_PREFIX = 'fix/'
    RESET_COMMENT = 'Closed by demo reset; the finding will be re-filed by the next scan.'
    COMMIT_MESSAGE = 'chore: reseed known-vulnerable pins for the remediation demo'

    def initialize(github:, repo:, db:, seeds:, out: $stdout, dry_run: false)
      @github = github
      @repo = repo
      @db = db
      @seeds = seeds
      @out = out
      @dry_run = dry_run
    end

    # Runs the four steps in order and returns how much each one did (or, on a
    # dry run, would have done).
    def call
      prs_closed, branches_deleted = close_pull_requests
      issues_closed = close_issues
      pins_restored = restore_pins
      rows_deleted = clear_database
      { prs_closed: prs_closed, branches_deleted: branches_deleted, issues_closed: issues_closed,
        pins_restored: pins_restored, rows_deleted: rows_deleted }
    end

    private

    # Devin opens its pull requests from fix/ branches; every other pull request stays open.
    def close_pull_requests
      pulls = @github.open_pull_requests(@repo).select { |pull| pull.head_branch.to_s.start_with?(FIX_BRANCH_PREFIX) }
      @out.puts "no open #{FIX_BRANCH_PREFIX} pull requests" if pulls.empty?
      pulls.each { |pull| close_pull_request(pull) }
      [pulls.size, pulls.size]
    end

    def close_pull_request(pull)
      act('closed', 'close', "pull request ##{pull.number} (#{pull.head_branch})") do
        @github.close_pull_request(@repo, pull.number)
      end
      act('deleted', 'delete', "branch #{pull.head_branch}") { @github.delete_branch(@repo, pull.head_branch) }
    end

    def close_issues
      issues = @github.open_issues(@repo, label: LABEL)
      @out.puts "no open #{LABEL} issues" if issues.empty?
      issues.each do |issue|
        act('closed', 'close', "issue ##{issue.number} #{issue.title}") do
          @github.create_issue_comment(@repo, issue.number, RESET_COMMENT)
          @github.close_issue(@repo, issue.number)
        end
      end
      issues.size
    end

    # One commit puts every drifted pin back; a file already at its seeded
    # values is left untouched so a second run makes no commit.
    def restore_pins
      path = @seeds.fetch('repo_file')
      branch = @seeds.fetch('branch')
      file = @github.file_with_sha(@repo, path, ref: branch)
      text, restored = reseed(file.text)
      return skip("#{path} already has the seeded pins") if restored.empty?

      act('restored', 'restore', "#{restored.join(', ')} in #{path} on #{branch}") do
        @github.update_file(@repo, path, content: text, message: COMMIT_MESSAGE, sha: file.sha, branch: branch)
      end
      restored.size
    end

    # The requirements text with each seeded package's `name==version` line
    # rewritten, and the pins that changed.
    def reseed(text)
      restored = @seeds.fetch('packages').filter_map do |package, versions|
        pin = "#{package}==#{versions.fetch('seeded')}"
        reseeded = text.sub(/^#{Regexp.escape(package)}==\S+/, pin)
        next if reseeded == text

        text = reseeded
        pin
      end
      [text, restored]
    end

    # Sessions go first because they reference findings.
    def clear_database
      sessions = @db[:sessions].count
      findings = @db[:findings].count
      return skip('database already empty') if (sessions + findings).zero?

      act('deleted', 'delete', "#{sessions} sessions and #{findings} findings") { delete_rows }
      sessions + findings
    end

    def delete_rows
      @db.transaction do
        @db[:sessions].delete
        @db[:findings].delete
      end
    end

    # Prints why a step had nothing to do; the step's count is zero.
    def skip(reason)
      @out.puts reason
      0
    end

    # Prints one line for the action, running the block only when this is not a dry run.
    def act(did, would, subject)
      if @dry_run
        @out.puts "would #{would} #{subject}"
      else
        yield
        @out.puts "#{did} #{subject}"
      end
    end
  end
end
