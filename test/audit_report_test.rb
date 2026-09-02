# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class AuditReportTest < Minitest::Test
    FIXTURE = File.expand_path('fixtures/pip_audit/seeded_base_txt.json', __dir__)

    def setup
      @report = AuditReport.parse(File.read(FIXTURE))
    end

    def test_vulnerable_packages_are_the_four_seeded_pins
      packages = @report.vulnerable_packages

      assert_equal %w[flask paramiko requests urllib3], packages.map(&:name).sort
      assert_equal 6, urllib3.vulns.size
      assert_equal '2.4.0', urllib3.version
    end

    def test_vulns_carry_id_fix_versions_and_aliases
      vuln = urllib3.vulns.find { |v| v.id == 'PYSEC-2026-141' }

      assert_equal ['2.7.0'], vuln.fix_versions
      assert_equal %w[CVE-2026-44431 GHSA-qccp-gfcp-xxvc], vuln.aliases
      assert_equal 'GHSA-qccp-gfcp-xxvc', vuln.ghsa_id
    end

    def test_paramiko_has_no_fix_versions
      vuln = package('paramiko').vulns.fetch(0)

      assert_empty vuln.fix_versions
      assert_equal 'GHSA-r374-rxx8-8654', vuln.ghsa_id
    end

    def test_ghsa_id_is_nil_without_a_ghsa_alias
      vuln = AuditReport::Vuln.new('id' => 'PYSEC-1', 'fix_versions' => [], 'aliases' => ['CVE-2026-1'])

      assert_nil vuln.ghsa_id
    end

    def test_clean_packages_are_not_vulnerable
      refute_predicate @report.packages.find { |p| p.name == 'alembic' }, :vulnerable?
      assert_operator @report.packages.size, :>, @report.vulnerable_packages.size
    end

    def test_invalid_json_raises
      assert_raises(SLA::Error) { AuditReport.parse('not json') }
      assert_raises(SLA::Error) { AuditReport.parse('[]') }
    end

    private

    def urllib3
      package('urllib3')
    end

    def package(name)
      @report.vulnerable_packages.find { |p| p.name == name }
    end
  end
end
