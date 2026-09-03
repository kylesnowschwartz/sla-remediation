# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class RepairPromptTest < Minitest::Test
    PR_URL = 'https://github.com/kylesnowschwartz/superset/pull/21'
    BRANCH = 'fix/flask-sla-15'
    SHA = '5aa0f39f7a5ad355d0c404ad10d9c90d4ef072db'
    RUNS_URL = 'https://github.com/kylesnowschwartz/superset/actions/runs/33708851664/job'

    # The pytest tail from the flask 2.3.3 -> 3.1.3 pull request, whose
    # integration tests imported `escape` from flask in two test files.
    PYTEST_SUMMARY = <<~SUMMARY
      tests/integration_tests/dashboard_tests.py:26: in <module>
          from flask import Response, escape, url_for
      E   ImportError: cannot import name 'escape' from 'flask' (/opt/hostedtoolcache/Python/3.11.16/x64/lib/python3.11/site-packages/flask/__init__.py)
      tests/integration_tests/dashboards/security/security_dataset_tests.py:21: in <module>
          from flask import (
      E   ImportError: cannot import name 'escape' from 'flask' (/opt/hostedtoolcache/Python/3.11.16/x64/lib/python3.11/site-packages/flask/__init__.py)
      =========================== short test summary info ============================
      ERROR tests/integration_tests/dashboard_tests.py
      ERROR tests/integration_tests/dashboards/security/security_dataset_tests.py
      !!!!!!!!!!!!!!!!!!! Interrupted: 2 errors during collection !!!!!!!!!!!!!!!!!!!!
    SUMMARY

    FAILURES = [
      GitHubClient::FailedCheckRun.new(name: 'test-sqlite', details_url: "#{RUNS_URL}/100504329014",
                                       output: PYTEST_SUMMARY.chomp),
      GitHubClient::FailedCheckRun.new(name: 'test-postgres (current)', details_url: "#{RUNS_URL}/100504329015",
                                       output: nil)
    ].freeze

    FLASK_FIXTURE = <<~PROMPT
      The checks on your pull request https://github.com/kylesnowschwartz/superset/pull/21 (branch `fix/flask-sla-15`)
      are failing at commit 5aa0f39f7a5ad355d0c404ad10d9c90d4ef072db. The failed jobs are:

      - `test-sqlite` — https://github.com/kylesnowschwartz/superset/actions/runs/33708851664/job/100504329014

        ```
        tests/integration_tests/dashboard_tests.py:26: in <module>
            from flask import Response, escape, url_for
        E   ImportError: cannot import name 'escape' from 'flask' (/opt/hostedtoolcache/Python/3.11.16/x64/lib/python3.11/site-packages/flask/__init__.py)
        tests/integration_tests/dashboards/security/security_dataset_tests.py:21: in <module>
            from flask import (
        E   ImportError: cannot import name 'escape' from 'flask' (/opt/hostedtoolcache/Python/3.11.16/x64/lib/python3.11/site-packages/flask/__init__.py)
        =========================== short test summary info ============================
        ERROR tests/integration_tests/dashboard_tests.py
        ERROR tests/integration_tests/dashboards/security/security_dataset_tests.py
        !!!!!!!!!!!!!!!!!!! Interrupted: 2 errors during collection !!!!!!!!!!!!!!!!!!!!
        ```
      - `test-postgres (current)` — https://github.com/kylesnowschwartz/superset/actions/runs/33708851664/job/100504329015

      Fix these failures:

      1. Work on the same branch, `fix/flask-sla-15`, and push your fix to it; the
         checks will run again on the new commit. Do not open a new pull request,
         and never touch `apache/superset`.
      2. Keep the change limited to what the failures require. Do not change
         dependencies, source, or tests beyond what is needed to make these jobs
         pass.
      3. Explain each change, and why the failure required it, in a comment on
         the pull request.
      4. When the fix is pushed, provide your final structured output again in
         the same shape as before, with `breaking_changes` listing every source or
         test file you changed with the reason, and `tests_run` listing the test
         commands you ran.
    PROMPT

    def test_renders_the_flask_example_with_both_escape_import_errors
      prompt = RepairPrompt.render(pr_url: PR_URL, branch: BRANCH, sha: SHA, failures: FAILURES)

      assert_equal FLASK_FIXTURE, prompt
      assert_equal 2, prompt.scan("ImportError: cannot import name 'escape' from 'flask'").size
    end

    def test_lists_a_job_without_output_as_just_its_name_and_url
      prompt = RepairPrompt.render(pr_url: PR_URL, branch: BRANCH, sha: SHA, failures: [FAILURES.fetch(1)])

      assert_includes prompt, "The failed jobs are:\n\n- `test-postgres (current)` — #{RUNS_URL}/100504329015\n\n" \
                              'Fix these failures:'
      refute_includes prompt, '```'
    end

    def test_reads_the_template_once
      assert_same RepairPrompt.send(:template), RepairPrompt.send(:template)
    end
  end
end
