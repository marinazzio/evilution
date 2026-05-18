# frozen_string_literal: true

require "evilution/integration/loading/syntax_validator"

RSpec.describe Evilution::Integration::Loading::SyntaxValidator do
  subject(:validator) { described_class.new }

  describe "#call" do
    context "with syntactically valid source" do
      it "returns nil" do
        expect(validator.call("a = 1\n")).to be_nil
      end
    end

    context "with syntactically invalid source" do
      let(:invalid_source) { "def foo(\n" }

      it "returns a failure-shaped hash" do
        result = validator.call(invalid_source)

        expect(result).to eq(
          passed: false,
          error: "mutated source has syntax errors",
          error_class: "SyntaxError",
          error_backtrace: []
        )
      end

      it "marks the result as not passed" do
        expect(validator.call(invalid_source)[:passed]).to be false
      end

      it "reports the canonical error message" do
        expect(validator.call(invalid_source)[:error]).to eq("mutated source has syntax errors")
      end

      it "reports the SyntaxError error class" do
        expect(validator.call(invalid_source)[:error_class]).to eq("SyntaxError")
      end

      it "reports an empty error backtrace" do
        expect(validator.call(invalid_source)[:error_backtrace]).to eq([])
      end

      it "does not return nil for invalid source" do
        expect(validator.call(invalid_source)).not_to be_nil
      end
    end
  end
end
