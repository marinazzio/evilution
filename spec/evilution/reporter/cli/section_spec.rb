# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/section"

RSpec.describe Evilution::Reporter::CLI::Section do
  describe "#initialize" do
    it "stores title, fetcher, formatter as readers" do
      formatter = double("formatter")
      fetcher = ->(s) { s }
      title = "Hello:"
      section = described_class.new(title: title, fetcher: fetcher, formatter: formatter)
      expect(section.title).to eq(title)
      expect(section.fetcher).to eq(fetcher)
      expect(section.formatter).to eq(formatter)
    end

    it "accepts a callable title (lambda taking items)" do
      title = ->(items) { "Found #{items.length}:" }
      section = described_class.new(title: title, fetcher: ->(_) {}, formatter: double("f"))
      expect(section.title).to eq(title)
    end
  end
end
