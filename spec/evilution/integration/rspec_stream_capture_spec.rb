# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"
require "evilution/integration/rspec"

# EV-m6xc / GH #1627: RSpec only redirects its own output when the stream its
# configuration holds is the current `$stdout`. In-process isolation swaps
# `$stdout` for a null IO around each mutation, and `--preload` builds the
# configuration before that swap, so the two no longer match and RSpec writes
# its run output to the real stdout — ahead of the JSON document.
RSpec.describe "RSpec run output capture (integration)" do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  def write_file(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def build_mutation
    instance_double(
      Evilution::Mutation,
      file_path: "lib/thing.rb",
      original_source: File.read("lib/thing.rb"),
      mutated_source: File.read("lib/thing.rb"),
      diff: nil,
      line: 2
    )
  end

  before do
    write_file("lib/thing.rb", "class Thing\n  def call\n    1\n  end\nend\n")
    write_file("spec/thing_spec.rb", <<~SPEC)
      require "thing"

      RSpec.describe Thing do
        it "calls" do
          expect(Thing.new.call).to eq(1)
        end
      end
    SPEC
    $LOAD_PATH.unshift(File.expand_path("lib"))
  end

  # Stands in for the host configuration a preloaded spec_helper leaves behind:
  # built while `$stdout` was the real one, before isolation swapped it.
  def configuration_bound_to(stream)
    RSpec.configuration.instance_variable_set(:@output_stream, stream)
    RSpec.configuration.instance_variable_set(:@error_stream, stream)
  end

  it "keeps the run's output off a stream the host configured earlier" do
    host_stream = StringIO.new
    configuration_bound_to(host_stream)

    Evilution::Integration::RSpec.new(test_files: ["spec/thing_spec.rb"]).call(build_mutation)

    expect(host_stream.string).to eq("")
  end

  it "still reports the run's verdict" do
    configuration_bound_to(StringIO.new)

    result = Evilution::Integration::RSpec.new(test_files: ["spec/thing_spec.rb"]).call(build_mutation)

    expect(result[:passed]).to be(true)
  end

  # The guard that puts the host's streams back must keep working.
  it "leaves the host configuration as it found it" do
    host_stream = StringIO.new
    configuration_bound_to(host_stream)

    Evilution::Integration::RSpec.new(test_files: ["spec/thing_spec.rb"]).call(build_mutation)

    expect(RSpec.configuration.instance_variable_get(:@output_stream)).to be(host_stream)
  end
end
