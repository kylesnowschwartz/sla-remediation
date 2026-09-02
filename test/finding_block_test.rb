# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class FindingBlockTest < Minitest::Test
    FIXTURES = File.expand_path('fixtures/github', __dir__)

    def test_parse_reads_the_recorded_issue_body
      body = JSON.parse(File.read(File.join(FIXTURES, 'github_issues_opened.json'))).dig('issue', 'body')

      finding = FindingBlock.parse(body)

      assert_equal 'urllib3', finding.package
      assert_equal '2.4.0', finding.pinned
      assert_equal '2.7.0', finding.fix_version
      assert_equal %w[PYSEC-2026-141 PYSEC-2026-1998 PYSEC-2026-1994 PYSEC-2026-1996], finding.advisories
      assert_equal 'high', finding.severity
      assert_equal 'pip-audit', finding.source
      assert_equal 'pypi', finding.ecosystem
    end

    def test_ecosystem_is_read_when_present
      finding = FindingBlock.parse("```yaml\npackage: lodash\nseverity: low\necosystem: npm\n```")

      assert_equal 'npm', finding.ecosystem
    end

    def test_severity_is_lowercased
      finding = FindingBlock.parse("```yaml\npackage: flask\nseverity: Critical\n```")

      assert_equal 'critical', finding.severity
    end

    def test_fix_version_may_be_nil
      finding = FindingBlock.parse("```yaml\npackage: flask\npinned: 2.3.3\nfix_version:\nseverity: low\n```")

      assert_nil finding.fix_version
      assert_empty finding.advisories
      assert_nil finding.source
    end

    def test_only_the_first_yaml_block_is_read
      body = "```yaml\npackage: flask\nseverity: low\n```\n\n```yaml\npackage: other\nseverity: high\n```"

      assert_equal 'flask', FindingBlock.parse(body).package
    end

    def test_body_without_a_block_raises
      error = assert_raises(SLA::Error) { FindingBlock.parse('Just prose, no finding block.') }

      assert_match(/no yaml finding block/, error.message)
      assert_raises(SLA::Error) { FindingBlock.parse(nil) }
    end

    def test_missing_package_or_severity_raises
      error = assert_raises(SLA::Error) { FindingBlock.parse("```yaml\npinned: 2.4.0\n```") }

      assert_match(/missing package and severity/, error.message)
      assert_raises(SLA::Error) { FindingBlock.parse("```yaml\npackage: urllib3\n```") }
    end

    def test_invalid_yaml_raises
      assert_raises(SLA::Error) { FindingBlock.parse("```yaml\npackage: [\n```") }
    end
  end
end
