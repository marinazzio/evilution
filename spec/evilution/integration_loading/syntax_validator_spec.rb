# frozen_string_literal: true

require "evilution/integration/loading/syntax_validator"

RSpec.describe Evilution::Integration::Loading::SyntaxValidator do
  subject(:validator) { described_class.new }

  describe "#call" do
    it "returns nil when source is syntactically valid" do
      expect(validator.call("class Foo; end\n")).to be_nil
    end

    it "returns an error result hash when source has syntax errors" do
      result = validator.call("class Foo; def self.( end\n")

      expect(result).to eq(
        passed: false,
        error: "mutated source has syntax errors",
        error_class: "SyntaxError",
        error_backtrace: []
      )
    end

    it "treats empty source as valid" do
      expect(validator.call("")).to be_nil
    end

    it "detects unclosed blocks" do
      result = validator.call("def foo\n")

      expect(result[:passed]).to be false
      expect(result[:error_class]).to eq("SyntaxError")
    end
  end
end
