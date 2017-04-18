require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |t|
  t.test_files = FileList['tests/*_tests.rb']
  # There are some warnings from parslet code that make test output annoying
  t.warning = false
end
desc "Run unit tests"

Rake::TestTask.new(:integration_test) do |t|
  t.test_files = FileList['tests/integration/*_tests.rb']
  # There are some warnings from parslet code that make test output annoying
  t.warning = false
end
desc "Run integration tests (requires running Elasticsearch server)"
