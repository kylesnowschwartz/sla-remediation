# frozen_string_literal: true

require 'json'

module SLA
  # The recorded pip-audit report and GitHub advisories for the seeded fork,
  # wired together the way the scanner does it.
  module ScannerFixtures
    AUDIT_REPORT = File.expand_path('fixtures/pip_audit/seeded_base_txt.json', __dir__)
    ADVISORIES = File.expand_path('fixtures/github/advisories', __dir__)

    def audit_json
      File.read(AUDIT_REPORT)
    end

    def audit_report
      AuditReport.parse(audit_json)
    end

    def audited_package(name)
      audit_report.vulnerable_packages.find { |p| p.name == name }
    end

    def advisory_json(ghsa_id)
      File.read(File.join(ADVISORIES, "#{ghsa_id}.json"))
    end

    def advisory(ghsa_id)
      body = JSON.parse(advisory_json(ghsa_id))
      GitHubClient::Advisory.new(ghsa_id: body['ghsa_id'], cve_id: body['cve_id'],
                                 severity: body['severity'], summary: body['summary'])
    end

    def finding_for(name)
      package = audited_package(name)
      Finding.from_audit(package, advisories: package.vulns.map { |vuln| [vuln, advisory(vuln.ghsa_id)] })
    end
  end
end
