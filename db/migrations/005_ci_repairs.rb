# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:sessions) do
      add_column :pr_head_sha, String
      add_column :ci_repair_sha, String
      add_column :ci_repairs, Integer, default: 0, null: false
    end
  end
end
