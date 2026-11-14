# frozen_string_literal: true

require "evilution/integration/rspec"

RSpec.describe Evilution::Integration::RSpec::KillerFirst do
  let(:durations) { { "/p/a_spec.rb[1:1]" => 0.5 } }

  # An ordered run leaves the global ordering of the process; this suite's own
  # is put back.
  around do |example|
    registry = RSpec.configuration.ordering_registry
    global = registry.fetch(:global)
    example.run
  ensure
    registry.register(:global, global)
  end

  describe "#applies?" do
    it "applies to a run that stops at its first kill, with times to go by" do
      expect(described_class.new(stop_on_kill: true, durations: durations).applies?).to be(true)
    end

    it "does not apply to a run that goes through every example" do
      expect(described_class.new(stop_on_kill: false, durations: durations).applies?).to be(false)
    end

    it "does not apply with neither times nor killers" do
      expect(described_class.new(stop_on_kill: true, durations: {}).applies?).to be(false)
    end

    it "applies with killers alone" do
      killer_first = described_class.new(stop_on_kill: true, durations: {})
      killer_first.prioritize(["/p/a_spec.rb[1:2]"])

      expect(killer_first.applies?).to be(true)
    end

    it "no longer applies once the killers are taken back" do
      killer_first = described_class.new(stop_on_kill: true, durations: {})
      killer_first.prioritize(["/p/a_spec.rb[1:2]"])
      killer_first.prioritize(nil)

      expect(killer_first.applies?).to be(false)
    end

    it "does not apply where RSpec cannot run an ordering by name" do
      allow(Evilution::Integration::RSpec::ExampleOrder).to receive(:supported?).and_return(false)

      expect(described_class.new(stop_on_kill: true, durations: durations).applies?).to be(false)
    end
  end

  describe "#during" do
    let(:registry) { RSpec.configuration.ordering_registry }

    it "makes the killer-first ordering the global one, and the named one, for the run" do
      killer_first = described_class.new(stop_on_kill: true, durations: durations)

      seen = killer_first.during(true) { [registry.fetch(:global), registry.fetch(:evilution_killer_first)] }

      expect(seen.first).to be_a(Evilution::Integration::RSpec::ExampleOrder)
      expect(seen.last).to be(seen.first)
    end

    def example(scoped_id)
      double("Example", metadata: { rerun_file_path: "/p/a_spec.rb", scoped_id: scoped_id })
    end

    it "runs the killers it was given first during the run, and keeps the defined order after it" do
      killer_first = described_class.new(stop_on_kill: true, durations: {})
      killer_first.prioritize(["/p/a_spec.rb[1:2]"])
      first = example("1:1")
      killer = example("1:2")
      ordering = nil

      during = killer_first.during(true) do
        ordering = registry.fetch(:global)
        ordering.order([first, killer])
      end

      expect(during).to eq([killer, first])
      expect(ordering.order([first, killer])).to eq([first, killer])
    end

    it "leaves the defined ordering the global one afterwards, even when the run raises" do
      killer_first = described_class.new(stop_on_kill: true, durations: durations)

      expect { killer_first.during(true) { raise "boom" } }.to raise_error("boom")
      expect(registry.fetch(:global)).to be(registry.fetch(:defined))
    end

    it "leaves the ordering alone for a run that is not ordered" do
      before = registry.fetch(:global)

      result = described_class.new(stop_on_kill: true, durations: durations).during(false) { :ran }

      expect(result).to eq(:ran)
      expect(registry.fetch(:global)).to be(before)
    end
  end
end
