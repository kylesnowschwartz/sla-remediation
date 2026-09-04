# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class PlaybookTest < Minitest::Test
    RULES = [
      'never against `apache/superset`',
      'Never open a pull request against `apache/superset`',
      '`uv pip compile pyproject.toml requirements/base.in -o requirements/base.txt`',
      'If the full recompile moves unrelated pins, fall back to editing',
      'strip the `-e ./superset-core` line into a temp file',
      '`pip-audit --disable-pip --no-deps -r`',
      'Reference the issue with "Fixes #<issue number>"',
      'search `requirements/`, `pyproject.toml`, `superset-core/pyproject.toml`',
      'the lowest release of the new major series',
      'preferring the latest release in the same major series',
      'Run the test files that import or exercise the changed code with `pytest <paths>`',
      'say so in the pull request and rely on CI; do not skip the change',
      'Do not modify any other dependencies or source files.',
      'Do not run the full test suite; CI on the pull request runs the relevant unit tests.',
      'make no source changes beyond what the upgrade breaks',
      'Other pre-existing findings are out of scope',
      '(`breaking_changes`)',
      '(`tests_run`)'
    ].freeze
    SECTIONS = ['## Procedure', '## Specifications', '## Advice', '## Forbidden Actions',
                '## Required from User'].freeze

    def test_title_and_macro
      assert_equal 'SLA dependency remediation (pip-audit)', Playbook.title
      assert_equal '!remediate-pip', Playbook.macro
      assert_match(/\A![A-Za-z0-9_-]+\z/, Playbook.macro)
    end

    def test_body_is_the_playbook_markdown_without_erb
      body = Playbook.body

      assert_equal File.read(Playbook::PATH), body
      assert_same body, Playbook.body
      refute_includes body, '<%'
      refute_includes body, '%>'
    end

    def test_body_has_the_recommended_sections
      SECTIONS.each { |section| assert_includes Playbook.body, section }
    end

    def test_body_keeps_every_rule_of_the_full_prompt
      RULES.each { |rule| assert_includes Playbook.body, rule }
    end

    def test_body_handles_both_major_version_cases
      assert_includes Playbook.body, 'If the task prompt says the fix crosses a major version'
      assert_includes Playbook.body, 'Otherwise'
    end

    def test_schema_is_the_remediation_result_schema
      assert_same RemediationPrompt.schema, Playbook.schema
    end

    def test_request_carries_title_body_macro_and_schema
      assert_equal({ title: Playbook.title, body: Playbook.body, macro: Playbook.macro,
                     structured_output_schema: Playbook.schema }, Playbook.request)
    end

    def test_current_compares_title_body_and_schema
      synced = DevinClient::Playbook.new(playbook_id: 'pb_1', title: Playbook.title, body: Playbook.body,
                                         macro: Playbook.macro, structured_output_schema: Playbook.schema)

      assert Playbook.current?(synced)
      refute Playbook.current?(synced.dup.tap { |p| p.body = "#{Playbook.body}\n- one more rule" })
      refute Playbook.current?(synced.dup.tap { |p| p.title = 'Something else' })
      refute Playbook.current?(synced.dup.tap { |p| p.structured_output_schema = nil })
    end
  end
end
