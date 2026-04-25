# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/world_filtered_examples"

RSpec.describe Evilution::Integration::RSpec::StateGuard::WorldFilteredExamples do
  let(:strategy) { described_class.new }

  before do
    @backup = if RSpec.world.instance_variable_defined?(:@filtered_examples)
                RSpec.world.instance_variable_get(:@filtered_examples).dup
              else
                :__missing__
              end
  end

  after do
    if @backup == :__missing__
      RSpec.world.remove_instance_variable(:@filtered_examples) if RSpec.world.instance_variable_defined?(:@filtered_examples)
    else
      RSpec.world.instance_variable_set(:@filtered_examples, @backup)
    end
  end

  it "snapshot returns a Set of object_ids of pre-existing keys" do
    a = Object.new
    b = Object.new
    RSpec.world.instance_variable_set(:@filtered_examples, { a => 1, b => 2 })
    snap = strategy.snapshot
    expect(snap).to eq(Set.new([a.object_id, b.object_id]))
  end

  it "snapshot returns nil when ivar is missing" do
    RSpec.world.remove_instance_variable(:@filtered_examples) if RSpec.world.instance_variable_defined?(:@filtered_examples)
    expect(strategy.snapshot).to be_nil
  end

  it "release removes only keys added after snapshot" do
    pre = Object.new
    RSpec.world.instance_variable_set(:@filtered_examples, { pre => 1 })
    snap = strategy.snapshot

    new_key = Object.new
    RSpec.world.instance_variable_get(:@filtered_examples)[new_key] = 2

    strategy.release(snap)

    fe = RSpec.world.instance_variable_get(:@filtered_examples)
    expect(fe.keys).to eq([pre])
  end
end
