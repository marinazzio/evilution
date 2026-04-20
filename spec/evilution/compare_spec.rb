# frozen_string_literal: true

require "evilution/compare"
require "evilution/compare/record"

RSpec.describe Evilution::Compare do
  describe "::InvalidInput" do
    it "is a StandardError subclass" do
      expect(described_class::InvalidInput.ancestors).to include(StandardError)
    end

    it "carries an index for the offending record" do
      err = described_class::InvalidInput.new("missing line", index: 3)
      expect(err.message).to eq("missing line")
      expect(err.index).to eq(3)
    end
  end
end

RSpec.describe Evilution::Compare::Record do
  let(:attrs) do
    {
      source: :evilution,
      file_path: "lib/foo.rb",
      line: 42,
      status: :killed,
      fingerprint: "abc123",
      operator: "Arithmetic::Swap",
      diff_body: "- a + b\n+ a - b",
      raw: { "operator" => "Arithmetic::Swap" }
    }
  end

  it "carries all canonical fields" do
    record = described_class.new(**attrs)
    expect(record.source).to eq(:evilution)
    expect(record.file_path).to eq("lib/foo.rb")
    expect(record.line).to eq(42)
    expect(record.status).to eq(:killed)
    expect(record.fingerprint).to eq("abc123")
    expect(record.operator).to eq("Arithmetic::Swap")
    expect(record.diff_body).to eq("- a + b\n+ a - b")
    expect(record.raw).to eq({ "operator" => "Arithmetic::Swap" })
  end

  it "is frozen / immutable" do
    record = described_class.new(**attrs)
    expect { record.instance_variable_set(:@source, :mutant) }.to raise_error(FrozenError)
  end
end
