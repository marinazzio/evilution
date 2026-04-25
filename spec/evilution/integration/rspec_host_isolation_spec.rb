# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec"

RSpec.describe "Evilution::Integration::RSpec host isolation" do
  before do
    allow(RSpec.configuration).to receive(:add_formatter)
  end

  it "preserves pre-existing RSpec.world.@example_groups across a run" do
    # Pre-populate world with synthetic host entries
    backup = RSpec.world.instance_variable_get(:@example_groups).dup
    RSpec.world.instance_variable_set(:@example_groups, %i[host_pre_a host_pre_b])

    # Drive a run with no real spec to execute by stubbing Runner.run
    integration = Evilution::Integration::RSpec.new(test_files: ["spec/nonexistent_spec.rb"])
    allow(RSpec::Core::Runner).to receive(:run) do |_, _, _|
      # Simulate RSpec adding to the world during the run
      RSpec.world.instance_variable_get(:@example_groups).push(:added_during_run)
      0
    end
    allow(integration).to receive(:reset_examples)

    mutation = instance_double("Mutation", file_path: "lib/foo.rb")
    integration.send(:run_tests, mutation)

    # Pre-existing entries survive; entries added during run are removed.
    final_groups = RSpec.world.instance_variable_get(:@example_groups)
    expect(final_groups).to include(:host_pre_a, :host_pre_b)
    expect(final_groups).not_to include(:added_during_run)
  ensure
    RSpec.world.instance_variable_set(:@example_groups, backup) if backup
  end

  it "preserves pre-existing RSpec.world.@sources_by_path keys across a run" do
    src_backup = (RSpec.world.instance_variable_get(:@sources_by_path).dup if RSpec.world.instance_variable_defined?(:@sources_by_path))
    RSpec.world.instance_variable_set(:@sources_by_path, { "host_existing.rb" => :data })

    integration = Evilution::Integration::RSpec.new(test_files: ["spec/nonexistent_spec.rb"])
    allow(RSpec::Core::Runner).to receive(:run) do |_, _, _|
      RSpec.world.instance_variable_get(:@sources_by_path)["added_during_run.rb"] = :added
      0
    end
    allow(integration).to receive(:reset_examples)

    mutation = instance_double("Mutation", file_path: "lib/foo.rb")
    integration.send(:run_tests, mutation)

    keys = RSpec.world.instance_variable_get(:@sources_by_path).keys
    expect(keys).to include("host_existing.rb")
    expect(keys).not_to include("added_during_run.rb")
  ensure
    if src_backup
      RSpec.world.instance_variable_set(:@sources_by_path, src_backup)
    elsif RSpec.world.instance_variable_defined?(:@sources_by_path)
      RSpec.world.remove_instance_variable(:@sources_by_path)
    end
  end

  it "preserves pre-existing RSpec::ExampleGroups constants across a run" do
    RSpec::ExampleGroups.const_set(:HostPre, Class.new) unless RSpec::ExampleGroups.const_defined?(:HostPre)

    integration = Evilution::Integration::RSpec.new(test_files: ["spec/nonexistent_spec.rb"])
    allow(RSpec::Core::Runner).to receive(:run) do |_, _, _|
      RSpec::ExampleGroups.const_set(:AddedDuringRun, Class.new)
      0
    end
    allow(integration).to receive(:reset_examples)

    mutation = instance_double("Mutation", file_path: "lib/foo.rb")
    integration.send(:run_tests, mutation)

    expect(RSpec::ExampleGroups.const_defined?(:HostPre)).to be true
    expect(RSpec::ExampleGroups.const_defined?(:AddedDuringRun)).to be false
  ensure
    RSpec::ExampleGroups.send(:remove_const, :HostPre) if RSpec::ExampleGroups.const_defined?(:HostPre)
    RSpec::ExampleGroups.send(:remove_const, :AddedDuringRun) if RSpec::ExampleGroups.const_defined?(:AddedDuringRun)
  end
end
