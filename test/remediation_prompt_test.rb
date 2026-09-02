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
      assert_includes prompt, 'named `fix/urllib3-sla-4`'
      assert_includes prompt, 'Reference the issue with "Fixes #4".'
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

    def test_schema_fits_the_session_request_limit
      assert_operator JSON.generate(RemediationPrompt.schema).bytesize, :<, SCHEMA_SIZE_LIMIT
    end
  end
end
