require 'rake/testtask'
require 'commonmarker'
require 'fileutils'

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

task :build do
  layout = File.read(File.join(__dir__, 'tutorial', 'layout.html'))
  tutorial = File.read(File.join(__dir__, 'tutorial', 'build_a_query_parser.md'))
  html = CommonMarker.render_html(tutorial)

  # TODO: Figure out a better way to create a layout for a markdown document
  compiled = layout.gsub('<body></body>', "<body>#{html}</body>")

  FileUtils.mkdir_p('build')

  File.open(File.join(__dir__, 'build', 'index.html'), 'w') do |f|
    f.write(compiled)
  end
end
