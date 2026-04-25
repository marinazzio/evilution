# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/world_example_groups"

RSpec.describe Evilution::Integration::RSpec::StateGuard::WorldExampleGroups do
  let(:strategy) { described_class.new }

  before do
    @world_groups_backup = RSpec.world.instance_variable_get(:@example_groups).dup
  end

  after do
    RSpec.world.instance_variable_set(:@example_groups, @world_groups_backup)
  end

  it "snapshot returns a frozen dup of the example_groups array" do
    RSpec.world.instance_variable_set(:@example_groups, %i[host_a host_b])
    snap = strategy.snapshot
    expect(snap).to eq(%i[host_a host_b])
    expect(snap).to be_frozen
  end

  it "snapshot returns nil when @example_groups ivar is missing" do
    RSpec.world.remove_instance_variable(:@example_groups) if RSpec.world.instance_variable_defined?(:@example_groups)
    expect(strategy.snapshot).to be_nil
  ensure
    RSpec.world.instance_variable_set(:@example_groups, [])
  end

  it "release removes only entries added after snapshot, leaving pre-existing ones intact" do
    RSpec.world.instance_variable_set(:@example_groups, %i[host_a host_b])
    snap = strategy.snapshot

    groups = RSpec.world.instance_variable_get(:@example_groups)
    groups.push(:added_x, :added_y)

    strategy.release(snap)

    expect(RSpec.world.instance_variable_get(:@example_groups)).to eq(%i[host_a host_b])
  end

  it "release is a no-op when snapshot is nil" do
    RSpec.world.instance_variable_set(:@example_groups, %i[a b c])
    expect { strategy.release(nil) }.not_to raise_error
    expect(RSpec.world.instance_variable_get(:@example_groups)).to eq(%i[a b c])
  end
end
