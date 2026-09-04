# frozen_string_literal: true

require 'json_schemer'

require_relative 'test_helper'

module SLA
  class RemediationPromptTest < Minitest::Test
    REPO = 'kylesnowschwartz/superset'
    ADVISORIES = %w[PYSEC-2026-141 PYSEC-2026-1998 PYSEC-2026-1994 PYSEC-2026-1996].freeze
    SCHEMA_SIZE_LIMIT = 64 * 1024

    # A findings row as Webhook::Handler records it from github_issues_opened.json.
    FINDING_ROW = {
      id: 1, issue_number: 4, issue_title: 'test: webhook path (throwaway)',
      issue_url: 'https://github.com/kylesnowschwartz/superset/issues/4',
      package: 'urllib3', pinned: '2.4.0', fix_version: '2.7.0', severity: 'high', source: 'pip-audit',
      ecosystem: 'pypi', advisories: JSON.generate(ADVISORIES),
      opened_at: Time.utc(2026, 9, 2, 8, 25, 30), due_at: Time.utc(2026, 9, 4, 8, 25, 30), closed_at: nil,
      created_at: Time.utc(2026, 9, 2, 8, 25, 31)
    }.freeze

    SAMPLE_OUTPUT = {
      'package' => 'urllib3', 'from_version' => '2.4.0', 'to_version' => '2.7.0',
      'advisories_cleared' => ADVISORIES, 'lockfile_route' => 'direct_edit',
      'verification' => { 'tool' => 'pip-audit', 'clean' => true, 'remaining_findings' => ['paramiko 3.5.1'] },
      'pr_url' => 'https://github.com/kylesnowschwartz/superset/pull/2',
      'notes' => 'Recompiling moved unrelated pins, so the urllib3 line was edited directly.'
    }.freeze

    # Byte-identical to what `RemediationPrompt.render(FINDING_ROW, repo: REPO)`
    # produces for a fix inside the pinned major series.
    SAME_MAJOR_FIXTURE = <<~PROMPT
      In the repository kylesnowschwartz/superset there is an open issue #4
      titled "test: webhook path (throwaway)" (https://github.com/kylesnowschwartz/superset/issues/4). It was filed from pip-audit
      output and reports that the pinned version of `urllib3`
      (2.4.0) in `requirements/base.txt` is affected by the
      following advisories: PYSEC-2026-141, PYSEC-2026-1998, PYSEC-2026-1994, PYSEC-2026-1996. The lowest
      version that clears all of them is 2.7.0. Severity:
      high. Remediation is due by 2026-09-04 08:25 UTC under
      this repository's SECURITY-SLA.md policy.

      Branch: `fix/urllib3-sla-4`, off `master`.
      The fix stays within the same major version: change nothing but the `urllib3` pin.

      Follow the attached playbook.
    PROMPT

    def test_render_names_the_finding_and_the_rules
      prompt = RemediationPrompt.render(FINDING_ROW, repo: REPO)

      assert_includes prompt, "In the repository #{REPO} there is an open issue #4"
      assert_includes prompt, 'titled "test: webhook path (throwaway)" (https://github.com/kylesnowschwartz/superset/issues/4)'
      assert_includes prompt, 'pinned version of `urllib3`'
      assert_includes prompt, '(2.4.0) in `requirements/base.txt`'
      assert_includes prompt, "following advisories: #{ADVISORIES.join(', ')}."
      ADVISORIES.each { |advisory| assert_includes prompt, advisory }
      assert_includes prompt, 'version that clears all of them is 2.7.0'
      assert_includes prompt, "Severity:\nhigh."
      assert_includes prompt, 'Remediation is due by 2026-09-04 08:25 UTC'
      assert_includes prompt, 'Branch: `fix/urllib3-sla-4`, off `master`.'
      assert_includes prompt, 'Follow the attached playbook.'
    end

    def test_render_is_short_and_leaves_the_procedure_to_the_playbook
      prompt = RemediationPrompt.render(FINDING_ROW, repo: REPO)

      assert_operator prompt.lines.size, :<, 25
      refute_includes prompt, 'uv pip compile'
      refute_includes prompt, 'pip-audit --disable-pip'
      refute_includes prompt, 'apache/superset'
    end

    def test_render_of_a_same_major_finding_is_byte_identical_to_the_pre_major_path_prompt
      assert_equal SAME_MAJOR_FIXTURE, RemediationPrompt.render(FINDING_ROW, repo: REPO)
    end

    def test_render_of_a_same_major_finding_has_the_same_major_language
      prompt = RemediationPrompt.render(FINDING_ROW, repo: REPO)

      assert_includes prompt, 'The fix stays within the same major version: change nothing but the `urllib3` pin.'
      refute_includes prompt, 'crosses a major version'
    end

    def test_render_of_a_major_version_finding_has_the_major_path_language
      row = FINDING_ROW.merge(pinned: '2.3.3', fix_version: '3.1.3')
      prompt = RemediationPrompt.render(row, repo: REPO)

      assert_includes prompt, 'The fix crosses a major version (2.3.3 → 3.1.3)'
      assert_includes prompt, 'the minimal source and test changes the upgrade breaks are permitted'
      refute_includes prompt, 'stays within the same major version'
    end

    def test_render_of_a_major_version_finding_asks_for_breaking_changes_and_tests_run_in_the_close
      row = FINDING_ROW.merge(pinned: '2.3.3', fix_version: '3.1.3')
      prompt = RemediationPrompt.render(row, repo: REPO)

      assert_includes prompt, 'the structured output must include `breaking_changes` and `tests_run`.'
    end

    def test_render_of_a_same_major_finding_does_not_ask_for_breaking_changes_or_tests_run
      prompt = RemediationPrompt.render(FINDING_ROW, repo: REPO)

      refute_includes prompt, 'breaking_changes'
      refute_includes prompt, 'tests_run'
    end

    def test_render_leaves_no_erb_tags
      prompt = RemediationPrompt.render(FINDING_ROW, repo: REPO)

      refute_includes prompt, '<%'
      refute_includes prompt, '%>'
    end

    def test_render_formats_due_at_in_utc
      row = FINDING_ROW.merge(due_at: Time.new(2026, 9, 4, 18, 25, 30, '+10:00'))

      assert_includes RemediationPrompt.render(row, repo: REPO), 'due by 2026-09-04 08:25 UTC'
    end

    def test_schema_is_the_parsed_file_read_once
      schema = RemediationPrompt.schema

      assert_equal JSON.parse(File.read(RemediationPrompt::SCHEMA_PATH)), schema
      assert_same schema, RemediationPrompt.schema
    end

    def test_schema_is_valid_draft_07_and_accepts_a_remediation_result
      schema = RemediationPrompt.schema

      assert_equal 'http://json-schema.org/draft-07/schema#', schema['$schema']
      assert JSONSchemer.valid_schema?(schema), JSONSchemer.validate_schema(schema).to_a.inspect
      schemer = JSONSchemer.schema(schema)

      assert_empty schemer.validate(SAMPLE_OUTPUT).to_a
      refute schemer.valid?(SAMPLE_OUTPUT.merge('lockfile_route' => 'guess'))
      refute schemer.valid?(SAMPLE_OUTPUT.except('pr_url'))
      refute schemer.valid?(SAMPLE_OUTPUT.merge('verification' => { 'tool' => 'pip-audit' }))
    end

    def test_schema_accepts_breaking_changes_and_tests_run
      schemer = JSONSchemer.schema(RemediationPrompt.schema)
      output = SAMPLE_OUTPUT.merge(
        'breaking_changes' => [{ 'file' => 'superset/views/base.py', 'reason' => 'renamed keyword argument' }],
        'tests_run' => ['pytest tests/unit_tests/views/test_base.py']
      )

      assert_empty schemer.validate(output).to_a
    end

    def test_schema_accepts_output_without_breaking_changes_or_tests_run
      schemer = JSONSchemer.schema(RemediationPrompt.schema)

      assert_empty schemer.validate(SAMPLE_OUTPUT).to_a
    end

    def test_schema_fits_the_session_request_limit
      assert_operator JSON.generate(RemediationPrompt.schema).bytesize, :<, SCHEMA_SIZE_LIMIT
    end
  end
end
