# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:findings) do
      add_column :issue_title, String
      add_column :issue_url, String
      add_column :ecosystem, String, default: 'pypi'
    end

    alter_table(:sessions) do
      add_index :finding_id, unique: true
    end
  end
end
