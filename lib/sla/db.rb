# frozen_string_literal: true

require 'sequel'

Sequel.default_timezone = :utc
Sequel.extension :migration

module SLA
  # Sequel connection to the service database, migrated on connect.
  DB = Sequel.connect(ENV.fetch('SLA_DATABASE_URL', 'sqlite://db/sla.sqlite3'))

  Sequel::Migrator.run(DB, File.expand_path('../../db/migrations', __dir__))
end
