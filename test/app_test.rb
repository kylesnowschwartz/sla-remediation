# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class AppTest < Test
    def setup
      DB[:sessions].delete
      DB[:findings].delete
      ENV['SLA_REPO'] = 'kylesnowschwartz/superset'
    end

    def test_healthz_returns_ok
      get '/healthz'

      assert_equal 200, last_response.status
      assert_equal 'application/json', last_response.media_type
      assert_equal({ 'ok' => true }, JSON.parse(last_response.body))
    end

    def test_status_page_lists_the_findings_and_refreshes_itself
      finding_id = record_finding(8)
      record_finding(12)
      DB[:sessions].insert(finding_id: finding_id, devin_session_id: '812ce7c3f89f4e88bce68dc03c9dd462',
                           status: 'running', status_detail: 'waiting_for_user', started_at: Time.now.utc - 900,
                           last_polled_at: Time.now.utc, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9',
                           pr_state: 'open', pr_notified_at: Time.now.utc, outcome: 'settled')

      get '/'

      assert_equal 200, last_response.status
      assert_equal 'text/html', last_response.media_type
      body = last_response.body

      assert_includes body, '<meta http-equiv="refresh" content="15">'
      assert_includes body, '<link rel="stylesheet" href="/house-style.css">'
      assert_includes body, "localStorage.getItem('theme')"
      assert_includes body, '<h1>kylesnowschwartz/superset &middot; security SLA</h1>'
      assert_includes body, 'href="https://github.com/kylesnowschwartz/superset/issues/8">#8</a>'
      assert_includes body, 'href="https://github.com/kylesnowschwartz/superset/issues/12">#12</a>'
      assert_includes body, '[SLA high] urllib3 2.4.0 → 2.7.0'
      assert_includes body, 'href="https://app.devin.ai/sessions/812ce7c3f89f4e88bce68dc03c9dd462">settled</a>'
      assert_includes body, 'href="https://github.com/kylesnowschwartz/superset/pull/9">#9</a>'
      pr_link = 'href="https://github.com/kylesnowschwartz/superset/pull/9">#9</a>'
      assert_match(%r{#{Regexp.escape(pr_link)}\s*<span class="muted">open</span>}, body)
      assert_includes body, 'class="tag sla-met">[MET]</td>'
      assert_includes body, 'class="tag sla-waiting">[WAITING]</td>'
      assert_includes body, 'not dispatched'
      assert_equal 2, body.scan('class="detail"').size
      assert_includes body, 'id="f8"'
      assert_includes body, 'id="f12"'
      refute_match(/type="checkbox" id="f\d+" checked/, body)
      assert_equal 2, body.scan('<dt>title</dt>').size
      assert_equal 2, body.scan('<dt>filed</dt>').size
      assert_equal 1, body.scan('<dt>ACUs</dt>').size
    end

    def test_house_style_is_served
      get '/house-style.css'

      assert_equal 200, last_response.status
      assert_equal 'text/css', last_response.media_type
      assert_includes last_response.body, '--shell:'
    end

    private

    def record_finding(issue_number)
      DB[:findings].insert(issue_number: issue_number, issue_title: '[SLA high] urllib3 2.4.0 → 2.7.0',
                           issue_url: "https://github.com/kylesnowschwartz/superset/issues/#{issue_number}",
                           package: 'urllib3', pinned: '2.4.0', fix_version: '2.7.0', severity: 'high',
                           source: 'pip-audit', advisories: '["GHSA-qccp-gfcp-xxvc"]',
                           opened_at: Time.now.utc, due_at: Time.now.utc + 86_400, created_at: Time.now.utc)
    end
  end
end
