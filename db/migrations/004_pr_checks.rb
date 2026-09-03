# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:sessions) do
      add_column :pr_checks, String
      add_column :pr_checks_at, DateTime
      add_column :pr_merged_at, DateTime
    end
  end
end
