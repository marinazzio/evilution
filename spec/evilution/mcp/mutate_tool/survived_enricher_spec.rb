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
  end
end
