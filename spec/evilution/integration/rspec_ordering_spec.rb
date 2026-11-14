# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/rspec"

# A mutation's run that stops at its first kill tries the examples that killed
# its neighbours first, then the cheapest; it reports which example killed and
# how many examples ran.
RSpec.describe Evilution::Integration::RSpec, "killer-first ordering" do
  # An ordered run leaves the global ordering of the process it runs in; this
  # suite's own is put back.
  around do |example|
    registry = RSpec.configuration.ordering_registry
    global = registry.fetch(:global)
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  ensure
    registry.register(:global, global)
  end

  let(:order_name) { Evilution::Integration::RSpec::ExampleOrder::NAME.to_s }
  let(:durations) { { "/p/thing_spec.rb[1:1]" => 0.5 } }

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

  # Records the arguments of each RSpec run, and the ordering RSpec would find
  # under its name while the run is under way, answering with the queued exit
  # statuses.
  def stub_runs(*statuses)
    captured = []
    queue = statuses.dup
    allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
      registry = RSpec.configuration.ordering_registry
      ordering = registry.has_strategy?(order_name.to_sym) ? registry.fetch(order_name.to_sym) : nil
      captured << { args: args, ordering: ordering }
      queue.shift || 0
    end
    captured
  end

  def narrowing_applier
    applier = instance_double(Evilution::Integration::RSpec::ExampleFilterApplier::Custom)
    allow(applier).to receive(:call).and_return(["spec/thing_spec.rb:9"])
    applier
  end

  def integration(stop_on_kill: true, example_durations: durations, **)
    described_class.new(test_files: ["spec/thing_spec.rb"], stop_on_kill: stop_on_kill,
                        example_durations: example_durations, **)
  end

  def order_of(args)
    args[args.index("--order") + 1]
  end

  before do
    allow(RSpec).to receive(:clear_examples)
    write_file("lib/thing.rb", "class Thing\n  def call\n    1\n  end\nend\n")
    write_file("spec/thing_spec.rb", "RSpec.describe Thing do\nend\n")
    allow(Evilution::Integration::RSpec::ExampleIds).to receive(:executed_count).and_return(0)
  end

  describe "the order a run asks for" do
    it "is killer-first when the run stops at its first kill" do
      captured = stub_runs(1)

      integration.call(build_mutation)

      expect(order_of(captured.first[:args])).to eq(order_name)
    end

    it "is the defined order when the run goes through every example" do
      captured = stub_runs(1)

      integration(stop_on_kill: false).call(build_mutation)

      expect(order_of(captured.first[:args])).to eq("defined")
    end

    it "is the defined order when there is neither a killer nor a duration to go by" do
      captured = stub_runs(1)

      integration(example_durations: {}).call(build_mutation)

      expect(order_of(captured.first[:args])).to eq("defined")
    end

    it "is killer-first with killers but no durations" do
      captured = stub_runs(1)
      checked = integration(example_durations: {})
      checked.prioritize(["/p/thing_spec.rb[1:2]"])

      checked.call(build_mutation)

      expect(order_of(captured.first[:args])).to eq(order_name)
    end

    it "is the defined order where RSpec cannot run an ordering by name" do
      allow(Evilution::Integration::RSpec::ExampleOrder).to receive(:supported?).and_return(false)
      captured = stub_runs(1)

      integration.call(build_mutation)

      expect(order_of(captured.first[:args])).to eq("defined")
    end

    # The command is what a reader runs to reproduce the verdict, and the
    # ordering exists only inside evilution.
    it "reports the command in the defined order" do
      stub_runs(1)

      result = integration.call(build_mutation)

      expect(result[:test_command]).to eq("rspec --format progress --no-color --order defined spec/thing_spec.rb")
    end

    # A survivor's confirming run decides its verdict on every example of the
    # file, whatever the order; it is left as it always ran.
    it "confirms a survivor in the defined order" do
      captured = stub_runs(0, 0)

      integration(example_filter_applier: narrowing_applier).call(build_mutation)

      expect(captured.map { |run| order_of(run[:args]) }).to eq([order_name, "defined"])
    end
  end

  describe "the ordering RSpec finds during the run" do
    def example(scoped_id)
      double("Example", metadata: { rerun_file_path: "/p/thing_spec.rb", scoped_id: scoped_id })
    end

    it "runs the given killers first" do
      checked = integration(example_durations: { "/p/thing_spec.rb[1:1]" => 0.1, "/p/thing_spec.rb[1:2]" => 9.0 })
      checked.prioritize(["/p/thing_spec.rb[1:2]"])
      cheap = example("1:1")
      killer = example("1:2")
      seen = nil
      allow(RSpec::Core::Runner).to receive(:run) do
        seen = RSpec.configuration.ordering_registry.fetch(order_name.to_sym).order([cheap, killer])
        1
      end

      checked.call(build_mutation)

      expect(seen).to eq([killer, cheap])
    end

    # RSpec applies `--order` only to the first run in a process that names
    # one, and a process that ran RSpec before -- the canary -- has had its.
    it "is the global ordering during the run, whatever an earlier run forced" do
      global = nil
      allow(RSpec::Core::Runner).to receive(:run) do
        global = RSpec.configuration.ordering_registry.fetch(:global)
        1
      end

      integration.call(build_mutation)

      expect(global).to be_a(Evilution::Integration::RSpec::ExampleOrder)
    end

    it "leaves the defined order the global one after the run" do
      stub_runs(1)

      integration.call(build_mutation)

      registry = RSpec.configuration.ordering_registry
      expect(registry.fetch(:global)).to be(registry.fetch(:defined))
    end

    it "keeps the defined order once the run is over" do
      captured = stub_runs(1)
      checked = integration(example_durations: { "/p/thing_spec.rb[1:1]" => 9.0, "/p/thing_spec.rb[1:2]" => 0.1 })
      first = example("1:1")
      second = example("1:2")

      checked.call(build_mutation)

      expect(captured.first[:ordering].order([first, second])).to eq([first, second])
    end
  end

  describe "what the run reports" do
    let(:detector) do
      instance_double(Evilution::Integration::CrashDetector, killing_id: "/p/thing_spec.rb[1:2]", raised_quit?: false,
                                                             only_crashes?: false)
    end
    let(:lifecycle) { instance_double(Evilution::Integration::RSpec::CrashDetectorLifecycle, register: detector) }

    it "names the example that killed" do
      stub_runs(1)

      result = integration(crash_detector_lifecycle: lifecycle).call(build_mutation)

      expect(result[:killing_example]).to eq("/p/thing_spec.rb[1:2]")
    end

    it "names no example when none killed" do
      allow(detector).to receive(:killing_id).and_return(nil)
      stub_runs(0)

      result = integration(crash_detector_lifecycle: lifecycle).call(build_mutation)

      expect(result).not_to have_key(:killing_example)
    end

    it "counts the examples that ran" do
      allow(Evilution::Integration::RSpec::ExampleIds).to receive(:executed_count).and_return(4)
      stub_runs(1)

      expect(integration.call(build_mutation)[:examples_run]).to eq(4)
    end

    it "counts the examples of a survivor's confirming run as well" do
      allow(Evilution::Integration::RSpec::ExampleIds).to receive(:executed_count).and_return(1, 6)
      stub_runs(0, 0)

      result = integration(example_filter_applier: narrowing_applier).call(build_mutation)

      expect(result[:examples_run]).to eq(7)
    end

    it "counts nothing for a confirmed survivor where RSpec cannot list its examples" do
      allow(Evilution::Integration::RSpec::ExampleIds).to receive(:executed_count).and_return(nil)
      stub_runs(0, 0)

      result = integration(example_filter_applier: narrowing_applier).call(build_mutation)

      expect(result).not_to have_key(:examples_run)
    end

    it "counts nothing where RSpec cannot list its examples" do
      allow(Evilution::Integration::RSpec::ExampleIds).to receive(:executed_count).and_return(nil)
      stub_runs(1)

      expect(integration.call(build_mutation)).not_to have_key(:examples_run)
    end
  end
end
