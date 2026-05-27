# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::SurvivedEnricher do
  let(:subject_stub) { double(name: "Foo#bar") }
  let(:mutation) do
    double(
      subject: subject_stub,
      file_path: "lib/foo.rb",
      line: 12,
      operator_name: "some_op"
    )
  end
  let(:result) { double(mutation: mutation) }

  describe ".call" do
    it "no-ops when survived is absent" do
      data = {}
      described_class.call(data, [result], double)
      expect(data).to eq({})
    end

    it "no-ops when survived is not an array" do
      data = { "survived" => "nope" }
      described_class.call(data, [result], double)
      expect(data["survived"]).to eq("nope")
    end

    it "adds subject, resolved spec_file, and next_step" do
      data = { "survived" => [{}] }
      resolver = double
      allow(resolver).to receive(:call).with("lib/foo.rb").and_return("spec/foo_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      described_class.call(data, [result], config)
      entry = data["survived"].first
      expect(entry["subject"]).to eq("Foo#bar")
      expect(entry["spec_file"]).to eq("spec/foo_spec.rb")
      expect(entry["next_step"]).to include("spec/foo_spec.rb", "lib/foo.rb:12", "Foo#bar", "some_op")
    end

    it "honours an explicit spec override from config" do
      data = { "survived" => [{}] }
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(true)
      allow(config).to receive(:spec_files).and_return(["spec/custom_spec.rb"])

      described_class.call(data, [result], config)
      expect(data["survived"].first["spec_file"]).to eq("spec/custom_spec.rb")
    end

    it "caches resolver calls per file" do
      data = { "survived" => [{}, {}] }
      resolver = double
      allow(resolver).to receive(:call).and_return("spec/foo_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      described_class.call(data, [result, result], config)
      expect(resolver).to have_received(:call).once
    end

    it "emits a default next_step when no spec can be resolved" do
      data = { "survived" => [{}] }
      resolver = double
      allow(resolver).to receive(:call).and_return(nil)
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      described_class.call(data, [result], config)
      entry = data["survived"].first
      expect(entry).not_to have_key("spec_file")
      expect(entry["next_step"]).to include("the covering test file")
    end

    # Kills EV-2bx6 / GH #1193 index_to_fetch on survived_enricher.rb:16
    # (`survived_results[index]` -> `survived_results.fetch(index)`). When
    # there are MORE serialized entries than survived_results — e.g. JSON
    # was trimmed or survived_results was filtered — `[]` returns nil and
    # the entry is skipped; `.fetch` would raise IndexError and abort the
    # whole enrichment loop.
    it "skips trailing entries whose index exceeds survived_results length" do
      data = { "survived" => [{}, {}] }
      resolver = double
      allow(resolver).to receive(:call).with("lib/foo.rb").and_return("spec/foo_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      expect do
        described_class.call(data, [result], config)
      end.not_to raise_error

      expect(data["survived"][0]["subject"]).to eq("Foo#bar")
      expect(data["survived"][1]).to eq({})
    end

    it "skips entries whose survived_result is nil instead of crashing" do
      # Guards `next unless result`: a nil result at an index must be skipped,
      # not dereferenced. The surviving entry is enriched, the nil one is left bare.
      data = { "survived" => [{}, {}] }
      resolver = double
      allow(resolver).to receive(:call).with("lib/foo.rb").and_return("spec/foo_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      expect do
        described_class.call(data, [nil, result], config)
      end.not_to raise_error
      expect(data["survived"][0]).to eq({})
      expect(data["survived"][1]["subject"]).to eq("Foo#bar")
    end

    it "normalizes spec_files: drops empty strings and stringifies entries" do
      # Guards `.map(&:to_s)` (symbol entry must become a String) and
      # `.reject(&:empty?)` (a leading empty string must not win as the override).
      data = { "survived" => [{}] }
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(true)
      allow(config).to receive(:spec_files).and_return(["", :"spec/custom_spec.rb"])

      described_class.call(data, [result], config)
      spec_file = data["survived"].first["spec_file"]
      expect(spec_file).to eq("spec/custom_spec.rb")
      expect(spec_file).to be_a(String)
    end

    # Kills EV-vlbh / GH #1191 conditional_negation on
    # survived_enricher.rb:25 (`explicit_spec ? nil : resolver_for_integration`
    # -> `false ? nil : ...`). When an explicit spec override is provided the
    # build_resolver path must NOT instantiate a SpecResolver — explicit_spec
    # short-circuits resolver lookup in enrich_entry, so creating a resolver
    # would be wasted work and the test below pins the behavior.
    it "does not instantiate a SpecResolver when an explicit spec override is provided" do
      data = { "survived" => [{}] }
      config = double(integration: :rspec)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(true)
      allow(config).to receive(:spec_files).and_return(["spec/custom_spec.rb"])
      allow(Evilution::SpecResolver).to receive(:new).and_call_original

      described_class.call(data, [result], config)

      expect(Evilution::SpecResolver).not_to have_received(:new)
      expect(data["survived"].first["spec_file"]).to eq("spec/custom_spec.rb")
    end

    # Kills EV-vlbh / GH #1191 conditional_negation on
    # survived_enricher.rb:50 (`unless integration_class` -> `unless false`).
    # The mutated guard ALWAYS returns the default SpecResolver, bypassing
    # the integration's own baseline_options[:spec_resolver]. The Minitest
    # integration registers a custom resolver, so a successful kill shows
    # the registered resolver is consulted rather than a fresh default.
    it "uses the integration's configured spec_resolver instead of a fresh default" do
      data = { "survived" => [{}] }
      custom_resolver = double("custom_resolver")
      allow(custom_resolver).to receive(:call).with("lib/foo.rb").and_return("test/foo_test.rb")
      allow(Evilution::Integration::Minitest)
        .to receive(:baseline_options).and_return(spec_resolver: custom_resolver)
      config = double(integration: :minitest)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      described_class.call(data, [result], config)

      expect(custom_resolver).to have_received(:call).with("lib/foo.rb")
      expect(data["survived"].first["spec_file"]).to eq("test/foo_test.rb")
    end

    it "falls back to a fresh SpecResolver for an unknown integration" do
      # Guards line 50: an unknown integration has no registered class, so the
      # method must return a usable SpecResolver. If the return is dropped, or
      # the class itself is returned, enrich_entry's `resolver.call` would crash.
      data = { "survived" => [{}] }
      resolver = double
      allow(resolver).to receive(:call).with("lib/foo.rb").and_return("spec/foo_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      config = double(integration: :totally_unknown)
      allow(config).to receive(:respond_to?).with(:spec_files).and_return(false)

      expect do
        described_class.call(data, [result], config)
      end.not_to raise_error
      expect(data["survived"].first["spec_file"]).to eq("spec/foo_spec.rb")
    end
  end
end
