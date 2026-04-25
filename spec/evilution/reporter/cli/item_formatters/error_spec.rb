# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/item_formatters/error"

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::Error do
  describe "#format" do
    let(:mutation) { double("mutation", operator_name: "x", file_path: "f.rb", line: 1) }

    it "returns header alone when error_message is nil" do
      result = double("result", mutation: mutation, error_message: nil)
      expect(described_class.new.format(result)).to eq("  x: f.rb:1")
    end

    it "appends indented error_message when present" do
      result = double("result", mutation: mutation, error_message: "first line\nsecond line")
      out = described_class.new.format(result)
      expect(out).to eq("  x: f.rb:1\n    first line\n    second line")
    end
  end
end
