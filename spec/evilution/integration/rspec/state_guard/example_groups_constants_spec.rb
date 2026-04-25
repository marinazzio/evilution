# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/example_groups_constants"

RSpec.describe Evilution::Integration::RSpec::StateGuard::ExampleGroupsConstants do
  let(:strategy) { described_class.new }

  it "snapshot returns a Set of pre-existing constants on RSpec::ExampleGroups" do
    pre_existed = RSpec::ExampleGroups.const_defined?(:HostPreExisting)
    RSpec::ExampleGroups.const_set(:HostPreExisting, Class.new) unless pre_existed
    snap = strategy.snapshot
    expect(snap).to include(:HostPreExisting)
  ensure
    RSpec::ExampleGroups.send(:remove_const, :HostPreExisting) if !pre_existed && RSpec::ExampleGroups.const_defined?(:HostPreExisting)
  end

  it "release removes only constants added after snapshot, leaving pre-existing intact" do
    host_keep_pre_existed = RSpec::ExampleGroups.const_defined?(:HostKeep)
    RSpec::ExampleGroups.const_set(:HostKeep, Class.new) unless host_keep_pre_existed
    snap = strategy.snapshot

    RSpec::ExampleGroups.const_set(:AddedDuringRun, Class.new)

    strategy.release(snap)

    expect(RSpec::ExampleGroups.const_defined?(:HostKeep)).to be true
    expect(RSpec::ExampleGroups.const_defined?(:AddedDuringRun)).to be false
  ensure
    RSpec::ExampleGroups.send(:remove_const, :HostKeep) if !host_keep_pre_existed && RSpec::ExampleGroups.const_defined?(:HostKeep)
    RSpec::ExampleGroups.send(:remove_const, :AddedDuringRun) if RSpec::ExampleGroups.const_defined?(:AddedDuringRun)
  end

  it "release is a no-op when snapshot is nil" do
    untouched_pre_existed = RSpec::ExampleGroups.const_defined?(:Untouched)
    RSpec::ExampleGroups.const_set(:Untouched, Class.new) unless untouched_pre_existed
    expect { strategy.release(nil) }.not_to raise_error
    expect(RSpec::ExampleGroups.const_defined?(:Untouched)).to be true
  ensure
    RSpec::ExampleGroups.send(:remove_const, :Untouched) if !untouched_pre_existed && RSpec::ExampleGroups.const_defined?(:Untouched)
  end

  it "snapshot returns nil if RSpec::ExampleGroups is undefined" do
    hide_const("RSpec::ExampleGroups")
    expect(strategy.snapshot).to be_nil
  end
end
