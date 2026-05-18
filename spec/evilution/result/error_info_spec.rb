# frozen_string_literal: true

RSpec.describe Evilution::Result::ErrorInfo do
  describe ".from_fields" do
    it "returns nil when every field is nil" do
      expect(described_class.from_fields).to be_nil
    end

    it "builds a real ErrorInfo when a message is given" do
      info = described_class.from_fields(message: "boom")

      expect(info).to be_a(described_class)
      expect(info.message).to eq("boom")
      expect(info.klass).to be_nil
      expect(info.backtrace).to be_nil
    end

    it "builds a real ErrorInfo when only a class is given" do
      info = described_class.from_fields(klass: "SyntaxError")

      expect(info).to be_a(described_class)
      expect(info.klass).to eq("SyntaxError")
    end

    it "builds a real ErrorInfo when only a backtrace is given" do
      info = described_class.from_fields(backtrace: ["lib/foo.rb:1"])

      expect(info).to be_a(described_class)
      expect(info.backtrace).to eq(["lib/foo.rb:1"])
    end

    it "preserves all three fields when given together" do
      info = described_class.from_fields(message: "boom", klass: "RuntimeError", backtrace: ["lib/foo.rb:1"])

      expect(info.message).to eq("boom")
      expect(info.klass).to eq("RuntimeError")
      expect(info.backtrace).to eq(["lib/foo.rb:1"])
    end
  end

  describe "#initialize" do
    it "stores the message" do
      expect(described_class.new(message: "boom").message).to eq("boom")
    end

    it "stores the class" do
      expect(described_class.new(klass: "SyntaxError").klass).to eq("SyntaxError")
    end

    it "stores the backtrace" do
      backtrace = ["lib/foo.rb:10:in `bar'"]

      expect(described_class.new(backtrace: backtrace).backtrace).to eq(backtrace)
    end

    it "leaves the backtrace nil when none is given" do
      expect(described_class.new(message: "boom").backtrace).to be_nil
    end

    it "freezes the stored backtrace" do
      info = described_class.new(backtrace: ["lib/foo.rb:10"])

      expect(info.backtrace).to be_frozen
    end

    it "stores a distinct copy of the backtrace" do
      backtrace = ["lib/foo.rb:10"]
      info = described_class.new(backtrace: backtrace)

      backtrace << "lib/foo.rb:20"

      expect(info.backtrace).to eq(["lib/foo.rb:10"])
    end

    it "is frozen" do
      expect(described_class.new(message: "boom")).to be_frozen
    end
  end
end
