# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:sessions) do
      add_column :outcome, String
      add_column :pr_notified_at, DateTime
      add_column :structured_output_invalid, String, text: true
      add_column :poll_count, Integer, default: 0, null: false
    end
  end
end
