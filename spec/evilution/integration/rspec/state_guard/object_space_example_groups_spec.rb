# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/object_space_example_groups"

RSpec.describe Evilution::Integration::RSpec::StateGuard::ObjectSpaceExampleGroups do
  let(:strategy) { described_class.new }

  it "snapshot returns a Set of object_ids of existing ExampleGroup classes" do
    snap = strategy.snapshot
    expect(snap).to be_a(Set)
    expect(snap).to all(be_a(Integer))
  end

  it "release prunes constants and ivars from groups created after snapshot" do
    snap = strategy.snapshot

    new_group = Class.new(RSpec::Core::ExampleGroup) do
      const_set(:NewConst, :value)
      instance_variable_set(:@new_ivar, :value)
    end

    expect(new_group.constants(false)).to include(:NewConst)
    expect(new_group.instance_variables).to include(:@new_ivar)

    strategy.release(snap)

    expect(new_group.constants(false)).not_to include(:NewConst)
    expect(new_group.instance_variables).not_to include(:@new_ivar)
  end

  it "release does not touch groups in the snapshot" do
    pre_existing = Class.new(RSpec::Core::ExampleGroup) do
      const_set(:Untouched, :keep)
      instance_variable_set(:@untouched, :keep)
    end
    snap = strategy.snapshot
    expect(snap).to include(pre_existing.object_id)

    strategy.release(snap)

    expect(pre_existing.constants(false)).to include(:Untouched)
    expect(pre_existing.instance_variables).to include(:@untouched)
  end

  it "release is a no-op when snapshot is nil" do
    expect { strategy.release(nil) }.not_to raise_error
  end
end
