# frozen_string_literal: true

require_relative 'remediation_prompt'

module SLA
  # The Devin Playbook that holds the fixed remediation procedure: its title,
  # macro, markdown body, and the structured output schema it attaches. The
  # organization's copy is created and updated from these by bin/playbook-sync.
  class Playbook
    PATH = File.expand_path('../../prompts/remediate_dependency.playbook.md', __dir__)
    TITLE = 'SLA dependency remediation (pip-audit)'
    MACRO = '!remediate-pip'

    def self.title
      TITLE
    end

    def self.macro
      MACRO
    end

    def self.body
      @body ||= File.read(PATH)
    end

    def self.schema
      RemediationPrompt.schema
    end

    # The keyword arguments DevinClient#create_playbook and #update_playbook take.
    def self.request
      { title: title, body: body, macro: macro, structured_output_schema: schema }
    end

    # Whether an organization playbook already carries this title, body, and schema.
    def self.current?(playbook)
      playbook.title == title && playbook.body == body && playbook.structured_output_schema == schema
    end
  end
end
