# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/rspec"

# EV-f8h3 / GH #1624: per-mutation targeting runs a subset of the examples in a
# spec file. When the subset misses the example that would have caught the
# mutation, the mutation looks like a survivor it is not. Before a survivor is
# reported, it is re-run against the whole resolved spec file.
RSpec.describe "Survivor confirmation (integration)" do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  def write_file(path, contents = "")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def build_mutation
    instance_double(
      Evilution::Mutation,
      file_path: "lib/thing.rb",
      original_source: File.read("lib/thing.rb"),
      mutated_source: "# mutated\n",
      diff: nil,
      line: 3
    )
  end

  # Records the arguments of each RSpec run and answers with the queued exit
  # statuses, so a targeted run and a confirming run can differ.
  def stub_runs(*statuses)
    captured = []
    queue = statuses.dup
    allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
      captured << args
      queue.shift || 0
    end
    captured
  end

  # Narrows to one example; the applier stands in for the real filter.
  def narrowing_applier
    applier = instance_double(Evilution::Integration::RSpec::ExampleFilterApplier::Custom)
    allow(applier).to receive(:call).and_return(["spec/thing_spec.rb:9"])
    applier
  end

  def full_file_applier
    applier = instance_double(Evilution::Integration::RSpec::ExampleFilterApplier::Custom)
    allow(applier).to receive(:call) { |_mutation, files| files }
    applier
  end

  def integration(applier)
    Evilution::Integration::RSpec.new(test_files: ["spec/thing_spec.rb"], example_filter_applier: applier)
  end

  before do
    write_file("lib/thing.rb", "class Thing\n  def call\n    1\n  end\nend\n")
    write_file("spec/thing_spec.rb", "RSpec.describe Thing do\nend\n")
  end

  it "re-runs a survivor against the whole spec file" do
    captured = stub_runs(0, 0)

    integration(narrowing_applier).call(build_mutation)

    expect(captured.map(&:last)).to eq(["spec/thing_spec.rb:9", "spec/thing_spec.rb"])
  end

  # The confirming run is the one that decides: the example the targeted subset
  # missed is what makes this a kill.
  it "reports the verdict of the confirming run" do
    stub_runs(0, 1)

    result = integration(narrowing_applier).call(build_mutation)

    expect(result[:passed]).to be(false)
  end

  it "keeps the survivor when the whole file agrees" do
    stub_runs(0, 0)

    result = integration(narrowing_applier).call(build_mutation)

    expect(result[:passed]).to be(true)
  end

  it "names the confirming run in the reported command" do
    stub_runs(0, 0)

    result = integration(narrowing_applier).call(build_mutation)

    expect(result[:test_command]).to end_with("spec/thing_spec.rb")
  end

  it "does not re-run a mutation the targeted examples killed" do
    captured = stub_runs(1)

    integration(narrowing_applier).call(build_mutation)

    expect(captured.length).to eq(1)
  end

  # Nothing was narrowed, so the first run already saw every example.
  it "does not re-run when the targeted set is the whole file" do
    captured = stub_runs(0)

    integration(full_file_applier).call(build_mutation)

    expect(captured.length).to eq(1)
  end
end
