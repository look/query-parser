require 'rake/testtask'
require 'commonmarker'
require 'commonmarker/rouge'
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

  source_code = Dir[File.join(__dir__, "*.rb")].each_with_object({}) do |filename, obj|
    obj[File.basename(filename)] = File.readlines(filename)
  end

  svgs = Dir[File.join(__dir__, 'tutorial', '*.svg')].each_with_object({}) do |filename, obj|
    obj[File.basename(filename)] = File.read(filename)
  end

  # Why yes, I am manipulating markup with regular expressions in a tutorial about writing a parser.
  # Why do you ask?
  tutorial.gsub!(/^\s*{{svg="([a-z\-]+\.svg)"}}$/) do |s|
    filename = $1
    "\n\n#{svgs.fetch(filename)}"
  end

  tutorial.gsub!(/^\s*{{code="([a-z_]+\.rb):(\d+)-(\d+)"}}$/) do |s|
    filename = $1
    # Line numbers are 1 indexed
    start_line = Integer($2) - 1
    end_line = Integer($3) - 1
    lines = source_code.fetch(filename).slice(start_line..end_line)
    offset = lines.first.index(/[^ ]/)
    lines.map! { |l| l[offset, l.length] || "\n" }
    %Q(```ruby\n#{lines.join}````)
  end

  doc = CommonMarker::Rouge.render_doc(tutorial)

  doc.walk do |node|
    if node.type == :header
      text = []
      node.each do |subnode|
        if subnode.type == :text
          text << subnode.string_content
        end
      end

      # There seems to be only one :text subnode for headers
      id = text.map(&:split).flatten.map(&:downcase).map { |word| word.gsub(/[^a-z0-9 ]/, '') }.join('_')

      html = %Q(<h#{node.header_level} id="#{id}">#{text.join(' ')}</h#{node.header_level}>)
      new_node = ::CommonMarker::Node.new(:html)
      new_node.string_content = html
      node.insert_before(new_node)
      node.delete
    end
  end

  # TODO: Figure out a better way to create a layout for a markdown document
  compiled = layout.gsub('<body></body>', "<body>#{doc.to_html}#{generated_at_html}</body>")

  FileUtils.mkdir_p('build')

  File.open(File.join(__dir__, 'build', 'index.html'), 'w') do |f|
    f.write(compiled)
  end
end

task :deploy => :build do
  dest = File.join(__dir__, '..', 'lug', 'static', 'query-parser')
  FileUtils.mkdir_p(dest)
  FileUtils.cp_r(File.join(__dir__, 'build', '.'), dest)
end

def generated_at_html
  # A little white lie. Only accurate if committed before generation.
  git_revision = `git rev-parse HEAD`.chomp[0, 10]
  github_revision_url = "https://github.com/look/query-parser/commit/#{git_revision}"
  timestamp = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
  %Q(<p class="generated_at">Last generated at #{timestamp} from <a href="#{github_revision_url}">revision #{git_revision}</a>.</p>)
end
