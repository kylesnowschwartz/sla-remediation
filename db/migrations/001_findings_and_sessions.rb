# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:findings) do
      primary_key :id
      Integer :issue_number, null: false, unique: true
      String :package
      String :pinned
      String :fix_version
      String :severity
      String :source
      String :advisories, text: true
      DateTime :opened_at
      DateTime :due_at
      DateTime :closed_at
      DateTime :created_at, null: false
    end

    create_table(:sessions) do
      primary_key :id
      foreign_key :finding_id, :findings, null: false
      String :devin_session_id, unique: true
      String :status
      String :status_detail
      Float :acus_consumed
      String :pr_url
      String :pr_state
      String :structured_output, text: true
      DateTime :started_at
      DateTime :finished_at
      DateTime :last_polled_at
    end
  end
end
