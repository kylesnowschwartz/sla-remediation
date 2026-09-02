# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

desc 'Run rubocop and the Herb ERB linter'
task :lint do
  sh 'bundle exec rubocop'
  sh 'npx --yes @herb-tools/linter views/ "templates/**/*.erb"'
end

task default: %i[test lint]
