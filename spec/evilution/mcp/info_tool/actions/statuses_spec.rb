# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/mcp/info_tool/actions/statuses"

RSpec.describe Evilution::MCP::InfoTool::Actions::Statuses do
  def parse_body(response)
    JSON.parse(response.content.first[:text])
  end

  describe ".call" do
    it "returns the full glossary under 'statuses'" do
      body = parse_body(described_class.call)
      expect(body["statuses"].map { |s| s["status"] }).to match_array(
        %w[killed survived timeout error neutral equivalent unresolved unparseable]
      )
    end

    it "invokes StatusGlossary.entries (which runs the drift check)" do
      expect(Evilution::MCP::InfoTool::StatusGlossary).to receive(:entries).and_call_original
      described_class.call
    end

    it "propagates drift error when STATUSES diverges" do
      stub_const("Evilution::Result::MutationResult::STATUSES", %i[killed])
      expect { described_class.call }.to raise_error(Evilution::Error, /status glossary drift/)
    end

    it "ignores unknown kwargs via **" do
      expect { described_class.call(files: ["x.rb"]) }.not_to raise_error
    end
  end
end
