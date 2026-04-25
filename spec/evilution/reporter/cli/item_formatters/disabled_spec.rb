# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/item_formatters/disabled"

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::Disabled do
  describe "#format" do
    it "formats a Mutation directly as '  operator: file:line'" do
      mutation = double("mutation", operator_name: "binary_swap", file_path: "lib/y.rb", line: 7)
      expect(described_class.new.format(mutation)).to eq("  binary_swap: lib/y.rb:7")
    end
  end
end
