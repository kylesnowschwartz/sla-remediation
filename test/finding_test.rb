# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'scanner_fixtures'

module SLA
  class FindingTest < Minitest::Test
    include ScannerFixtures

    URLLIB3_GHSA_IDS = %w[
      GHSA-qccp-gfcp-xxvc GHSA-pq67-6m6q-mj2v GHSA-gm62-xv2j-4w53
      GHSA-48p4-8xcf-vxj5 GHSA-2xpw-w6gg-jr37 GHSA-38jv-5279-wg99
    ].freeze

    def test_urllib3_is_high_with_the_highest_fix_version
      finding = finding_for('urllib3')

      assert_equal 'urllib3', finding.package
      assert_equal '2.4.0', finding.pinned
      assert_equal 'high', finding.severity
      assert_equal '2.7.0', finding.fix_version
      assert_equal URLLIB3_GHSA_IDS, finding.advisories
      assert_equal 'pip-audit', finding.source
      assert_predicate finding, :fixable?
      assert_equal 'urllib3: Sensitive headers forwarded across origins in proxied low-level redirects',
                   finding.advisory_summaries['GHSA-qccp-gfcp-xxvc']
      assert_equal 'CVE-2026-44431', finding.cve_ids['GHSA-qccp-gfcp-xxvc']
    end

    def test_requests_is_medium
      finding = finding_for('requests')

      assert_equal 'medium', finding.severity
      assert_equal '2.33.0', finding.fix_version
      assert_equal 3, finding.advisories.size
    end

    def test_flask_is_low
      finding = finding_for('flask')

      assert_equal 'low', finding.severity
      assert_equal '3.1.3', finding.fix_version
      assert_equal ['GHSA-68rp-wp8r-4726'], finding.advisories
    end

    def test_paramiko_has_no_fixed_release
      finding = finding_for('paramiko')

      assert_equal 'low', finding.severity
      assert_nil finding.fix_version
      refute_predicate finding, :fixable?
    end

    def test_severity_is_the_highest_regardless_of_order
      package = audited_package('urllib3')
      medium = advisory('GHSA-pq67-6m6q-mj2v')
      high = advisory('GHSA-2xpw-w6gg-jr37')
      vuln = package.vulns.first

      assert_equal 'high', Finding.from_audit(package, advisories: [[vuln, medium], [vuln, high]]).severity
      assert_equal 'high', Finding.from_audit(package, advisories: [[vuln, high], [vuln, medium]]).severity
    end

    def test_fix_version_compares_as_a_version_not_a_string
      package = audited_package('urllib3')
      vulns = [
        AuditReport::Vuln.new('id' => 'A', 'fix_versions' => ['2.10.0'], 'aliases' => []),
        AuditReport::Vuln.new('id' => 'B', 'fix_versions' => ['2.9.1'], 'aliases' => [])
      ]
      pairs = vulns.map { |vuln| [vuln, advisory('GHSA-pq67-6m6q-mj2v')] }

      assert_equal '2.10.0', Finding.from_audit(package, advisories: pairs).fix_version
    end

    def test_issue_title_formats
      assert_equal '[SLA high] urllib3 2.4.0 → 2.7.0', finding_for('urllib3').issue_title
      assert_equal '[SLA low] paramiko 3.5.1: no fixed release', finding_for('paramiko').issue_title
    end

    def test_unknown_severity_is_ignored_when_another_advisory_is_rated
      package = audited_package('flask')
      vuln = package.vulns.first
      medium = advisory('GHSA-pq67-6m6q-mj2v')

      finding = Finding.from_audit(package, advisories: [[vuln, unknown_advisory], [vuln, medium]])

      assert_equal 'medium', finding.severity
      assert_predicate finding, :severity_rated?
      reversed = Finding.from_audit(package, advisories: [[vuln, medium], [vuln, unknown_advisory]])

      assert_equal 'medium', reversed.severity
    end

    def test_only_unknown_severities_default_to_low_and_unrated
      package = audited_package('flask')

      finding = Finding.from_audit(package, advisories: [[package.vulns.first, unknown_advisory]])

      assert_equal 'low', finding.severity
      refute_predicate finding, :severity_rated?
      assert_equal '[SLA low] flask 2.3.3 → 3.1.3', finding.issue_title
    end

    private

    def unknown_advisory
      GitHubClient::Advisory.new(ghsa_id: 'GHSA-xxxx-xxxx-xxxx', cve_id: nil, severity: 'unknown', summary: 'Unrated')
    end
  end
end
