# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/world_sources_by_path"

RSpec.describe Evilution::Integration::RSpec::StateGuard::WorldSourcesByPath do
  let(:strategy) { described_class.new }

  before do
    @backup = if RSpec.world.instance_variable_defined?(:@sources_by_path)
                RSpec.world.instance_variable_get(:@sources_by_path).dup
              else
                :__missing__
              end
  end

  after do
    if @backup == :__missing__
      RSpec.world.remove_instance_variable(:@sources_by_path) if RSpec.world.instance_variable_defined?(:@sources_by_path)
    else
      RSpec.world.instance_variable_set(:@sources_by_path, @backup)
    end
  end

  it "snapshot returns a Set of existing keys" do
    RSpec.world.instance_variable_set(:@sources_by_path, { "host/a.rb" => :a, "host/b.rb" => :b })
    snap = strategy.snapshot
    expect(snap).to be_a(Set)
    expect(snap).to eq(Set.new(["host/a.rb", "host/b.rb"]))
  end

  it "snapshot returns nil when ivar is missing" do
    RSpec.world.remove_instance_variable(:@sources_by_path) if RSpec.world.instance_variable_defined?(:@sources_by_path)
    expect(strategy.snapshot).to be_nil
  end

  it "release removes only keys added after snapshot, leaving pre-existing intact" do
    RSpec.world.instance_variable_set(:@sources_by_path, { "host/a.rb" => :a })
    snap = strategy.snapshot

    src = RSpec.world.instance_variable_get(:@sources_by_path)
    src["added.rb"] = :new

    strategy.release(snap)

    expect(RSpec.world.instance_variable_get(:@sources_by_path).keys).to eq(["host/a.rb"])
  end

  it "release is a no-op when snapshot is nil" do
    RSpec.world.instance_variable_set(:@sources_by_path, { "x" => 1 })
    expect { strategy.release(nil) }.not_to raise_error
    expect(RSpec.world.instance_variable_get(:@sources_by_path).keys).to eq(["x"])
  end
end
