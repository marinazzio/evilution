# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/item_formatters/result_location"

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::ResultLocation do
  describe "#format" do
    it "formats result.mutation as '  operator: file:line'" do
      mutation = double("mutation", operator_name: "literal_swap", file_path: "lib/x.rb", line: 100)
      result = double("result", mutation: mutation)
      expect(described_class.new.format(result)).to eq("  literal_swap: lib/x.rb:100")
    end
  end
end
