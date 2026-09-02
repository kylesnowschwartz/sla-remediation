# frozen_string_literal: true

require 'stringio'

require_relative 'test_helper'
require_relative 'scanner_fixtures'

module SLA
  class ScannerTest < Minitest::Test
    include ScannerFixtures

    REPO = 'kylesnowschwartz/superset'
    LABEL = 'sla-remediation'
    ISSUES_URL = "https://api.github.com/repos/#{REPO}/issues".freeze
    POLICY_TEXT = "```yaml\nsla_days:\n  critical: 2\n  high: 2\n  medium: 14\n  low: 30\n```\n"
    URLLIB3_ISSUE_BODY = "Filed earlier.\n\n```yaml\npackage: urllib3\npinned: \"2.4.0\"\nfix_version: \"2.7.0\"\n" \
                         "advisories:\n  - GHSA-qccp-gfcp-xxvc\nseverity: high\nsource: pip-audit\n```\n"

    def setup
      @out = StringIO.new
      @advisory_requests = Hash.new(0)
      stub_advisories
      @created = []
      @scanner = Scanner.new(github: GitHubClient.new(token: 'test-token'), policy: Policy.load(POLICY_TEXT),
                             repo: REPO, ref: 'master', audit_runner: ->(_text) { audit_json }, out: @out)
    end

    def test_findings_are_sorted_by_package_and_fetch_each_advisory_once
      findings = @scanner.findings("urllib3==2.4.0\n")

      assert_equal %w[flask paramiko requests urllib3], findings.map(&:package)
      assert_equal 11, @advisory_requests.size
      assert @advisory_requests.values.all? { |count| count == 1 }, @advisory_requests.inspect
    end

    def test_run_files_one_labeled_issue_per_vulnerable_package
      stub_open_issues([])
      stub_create_issue

      filed = @scanner.run(requirements_text: "urllib3==2.4.0\n")

      assert_equal 4, @created.size
      assert_equal %w[flask paramiko requests urllib3], filed.map(&:package)
      @created.each_with_index do |payload, index|
        finding = filed[index]

        assert_equal [LABEL], payload['labels']
        assert_equal finding.issue_title, payload['title']
        assert_match(/\A\[SLA (low|medium|high|critical)\] \S+ \S+( → \S+|: no fixed release)\z/, payload['title'])
        assert_round_trips finding, payload['body']
      end
      assert_equal ["filed #101 #{filed[0].issue_title}", "filed #102 #{filed[1].issue_title}",
                    "filed #103 #{filed[2].issue_title}", "filed #104 #{filed[3].issue_title}"], output_lines
    end

    def test_run_skips_packages_with_an_open_labeled_issue
      stub_open_issues([{ 'number' => 7, 'title' => 'urllib3', 'body' => URLLIB3_ISSUE_BODY, 'html_url' => 'u' },
                        { 'number' => 8, 'title' => 'prose only', 'body' => 'No block here.', 'html_url' => 'u' }])
      stub_create_issue

      filed = @scanner.run(requirements_text: "urllib3==2.4.0\n")

      assert_equal 3, @created.size
      assert_equal %w[flask paramiko requests], filed.map(&:package)
      assert_includes output_lines, 'skipped urllib3 (open issue #7)'
      assert_requested :get, ISSUES_URL, query: { state: 'open', labels: LABEL, per_page: '100' }
    end

    def test_dry_run_prints_instead_of_posting
      stub_open_issues([])

      filed = @scanner.run(requirements_text: "urllib3==2.4.0\n", dry_run: true)

      assert_equal 4, filed.size
      assert_not_requested :post, ISSUES_URL
      assert_equal 4, output_lines.grep(/\Awould file \[SLA /).size
      assert_includes @out.string, "```yaml\npackage: urllib3\npinned: \"2.4.0\"\nfix_version: \"2.7.0\"\n"
    end

    def test_run_reads_requirements_from_github_when_not_given
      contents_url = "https://api.github.com/repos/#{REPO}/contents/requirements/base.txt"
      body = { 'encoding' => 'base64', 'content' => Base64.strict_encode64("urllib3==2.4.0\n") }.to_json
      stub_request(:get, contents_url).with(query: { ref: 'master' })
                                      .to_return(status: 200, body: body, headers: json_header)
      stub_open_issues([])

      filed = @scanner.run(dry_run: true)

      assert_requested :get, contents_url, query: { ref: 'master' }
      assert_equal 4, filed.size
    end

    def test_rendered_body_for_paramiko_says_there_is_no_fixed_release
      body = @scanner.render_body(finding_for('paramiko'))

      assert_includes body, 'no fixed release exists yet'
      assert_includes body, 'The remediation window is 30 days for low findings, per SECURITY-SLA.md.'
      assert_includes body, '- GHSA-r374-rxx8-8654 (CVE-2026-44405): Paramiko rsakey.py allows the SHA-1 algorithm'
      assert_includes body, "pinned: \"3.5.1\"\nfix_version: null\n"
      assert_nil FindingBlock.parse(body).fix_version
    end

    def test_rendered_body_for_urllib3_lists_every_advisory
      body = @scanner.render_body(finding_for('urllib3'))

      assert_includes body, 'upgrading to 2.7.0 fixes all of them'
      assert_includes body, 'The remediation window is 2 days for high findings, per SECURITY-SLA.md.'
      assert_equal 6, body.scan(/^- GHSA-\S+ \(CVE-\S+\): /).size
      assert_includes body, "pinned: \"2.4.0\"\nfix_version: \"2.7.0\"\n"
      assert_equal %w[package pinned fix_version advisories severity source], YAMLBlock.first(body).keys
    end

    def test_rendered_body_notes_when_no_advisory_carries_a_severity_rating
      package = audited_package('flask')
      unrated = GitHubClient::Advisory.new(ghsa_id: 'GHSA-xxxx-xxxx-xxxx', cve_id: nil,
                                           severity: 'unknown', summary: 'Unrated')
      finding = Finding.from_audit(package, advisories: [[package.vulns.first, unrated]])

      body = @scanner.render_body(finding)

      assert_includes body,
                      'The remediation window is 30 days for low findings, per SECURITY-SLA.md ' \
                      '(no advisory carries a severity rating).'
      assert_equal 'low', FindingBlock.parse(body).severity
    end

    private

    def assert_round_trips(finding, body)
      block = FindingBlock.parse(body)

      assert_equal finding.package, block.package
      assert_equal finding.pinned, block.pinned
      if finding.fixable?
        assert_equal finding.fix_version, block.fix_version
      else
        assert_nil block.fix_version
      end
      assert_equal finding.severity, block.severity
      assert_equal finding.advisories, block.advisories
      assert_equal 'pip-audit', block.source
      assert_includes body, "pinned: \"#{finding.pinned}\""
      assert_includes body, finding.fixable? ? "fix_version: \"#{finding.fix_version}\"" : 'fix_version: null'
    end

    def stub_advisories
      stub_request(:get, %r{\Ahttps://api\.github\.com/advisories/GHSA-[\w-]+\z}).to_return do |request|
        ghsa_id = request.uri.path.split('/').last
        @advisory_requests[ghsa_id] += 1
        { status: 200, body: advisory_json(ghsa_id), headers: json_header }
      end
    end

    def stub_open_issues(issues)
      stub_request(:get, ISSUES_URL).with(query: { state: 'open', labels: LABEL, per_page: '100' })
                                    .to_return(status: 200, body: issues.to_json, headers: json_header)
    end

    def stub_create_issue
      stub_request(:post, ISSUES_URL).to_return do |request|
        payload = JSON.parse(request.body)
        @created << payload
        number = 100 + @created.size
        body = payload.merge('number' => number, 'html_url' => "https://github.com/#{REPO}/issues/#{number}").to_json
        { status: 201, body: body, headers: json_header }
      end
    end

    def output_lines
      @out.string.lines.map(&:chomp)
    end

    def json_header
      { 'Content-Type' => 'application/json' }
    end
  end
end
