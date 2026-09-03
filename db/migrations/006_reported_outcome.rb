# frozen_string_literal: true

Sequel.migration do
  up do
    from(:sessions).where(outcome: 'settled').update(outcome: 'reported')
  end

  down do
    from(:sessions).where(outcome: 'reported').update(outcome: 'settled')
  end
end
