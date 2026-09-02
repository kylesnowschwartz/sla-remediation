# frozen_string_literal: true

require 'open3'
require 'tempfile'

require_relative 'errors'

module SLA
  # Runs pip-audit over a requirements file and returns its JSON report.
  module PipAudit
    COMMAND = %w[uvx pip-audit --disable-pip --no-deps --format json -r].freeze
    # pip-audit exits 1 when it finds vulnerabilities; anything higher is a failure.
    SUCCESS_STATUSES = [0, 1].freeze
    EDITABLE_LINE = /\A\s*-e\b/

    # Audits the pins in the requirements text, without editable (`-e`) lines,
    # which point at local checkouts pip-audit can't resolve.
    def self.run(requirements_text)
      Tempfile.create(['requirements', '.txt']) do |file|
        file.write(requirements_text.each_line.grep_v(EDITABLE_LINE).join)
        file.flush

        stdout, stderr, status = Open3.capture3(*COMMAND, file.path)
        unless SUCCESS_STATUSES.include?(status.exitstatus)
          raise Error, "pip-audit exited #{status.exitstatus}: #{stderr.strip}"
        end

        stdout
      end
    end
  end
end
