# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/mcp/info_tool/actions/tests"

RSpec.describe Evilution::MCP::InfoTool::Actions::Tests do
  def parse_body(response)
    JSON.parse(response.content.first[:text])
  end

  describe ".call" do
    it "returns a config_error response when files is nil" do
      response = described_class.call(files: nil, spec: nil, integration: nil, skip_config: nil)
      expect(response.error?).to be true
      expect(parse_body(response)["error"]["message"]).to eq("files is required")
    end

    it "returns explicit spec_files when config.spec_files is set" do
      config = instance_double(Evilution::Config, spec_files: ["spec/foo_spec.rb"])
      allow(Evilution::MCP::InfoTool::ConfigFactory).to receive(:tests).and_return(config)

      response = described_class.call(
        files: ["lib/foo.rb"], spec: ["spec/foo_spec.rb"], integration: nil, skip_config: nil
      )
      body = parse_body(response)
      expect(body["specs"]).to eq([{ "source" => nil, "spec" => "spec/foo_spec.rb" }])
      expect(body["unresolved"]).to eq([])
      expect(body["total_sources"]).to eq(1)
      expect(body["total_specs"]).to eq(1)
    end

    it "auto-resolves specs via resolver when config.spec_files is empty" do
      config = instance_double(Evilution::Config, spec_files: [], integration: :unknown_int)
      allow(Evilution::MCP::InfoTool::ConfigFactory).to receive(:tests).and_return(config)
      resolver = instance_double("Evilution::SpecResolver")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:call).with("lib/a.rb").and_return("spec/a_spec.rb")
      allow(resolver).to receive(:call).with("lib/b.rb").and_return(nil)

      response = described_class.call(
        files: ["lib/a.rb", "lib/b.rb"], spec: nil, integration: nil, skip_config: nil
      )
      body = parse_body(response)
      expect(body["specs"]).to eq([{ "source" => "lib/a.rb", "spec" => "spec/a_spec.rb" }])
      expect(body["unresolved"]).to eq(["lib/b.rb"])
      expect(body["total_sources"]).to eq(2)
      expect(body["total_specs"]).to eq(1)
    end

    it "deduplicates total_specs in the explicit-specs branch" do
      config = instance_double(
        Evilution::Config, spec_files: ["spec/foo_spec.rb", "spec/foo_spec.rb"]
      )
      allow(Evilution::MCP::InfoTool::ConfigFactory).to receive(:tests).and_return(config)

      response = described_class.call(
        files: ["lib/foo.rb"],
        spec: ["spec/foo_spec.rb", "spec/foo_spec.rb"],
        integration: nil, skip_config: nil
      )
      body = parse_body(response)
      expect(body["total_specs"]).to eq(1)
    end

    it "uses integration class's baseline spec_resolver when available" do
      config = instance_double(Evilution::Config, spec_files: [], integration: :rspec)
      allow(Evilution::MCP::InfoTool::ConfigFactory).to receive(:tests).and_return(config)
      custom_resolver = instance_double("Evilution::SpecResolver", call: "test/foo_test.rb")
      integration_class = Evilution::Runner::INTEGRATIONS[:rspec]
      allow(integration_class).to receive(:baseline_options).and_return(spec_resolver: custom_resolver)

      described_class.call(files: ["lib/foo.rb"], spec: nil, integration: nil, skip_config: nil)

      expect(custom_resolver).to have_received(:call).with("lib/foo.rb")
    end
  end
end
