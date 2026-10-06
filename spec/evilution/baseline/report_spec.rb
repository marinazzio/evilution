# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Baseline::Report do
  describe ".build" do
    it "reports a passing run with no failures" do
      expect(described_class.build(passed: true))
        .to eq(passed: true, failure_count: 0, failures: [], error: nil)
    end

    it "coerces a truthy pass flag to true" do
      expect(described_class.build(passed: 0)[:passed]).to be(true)
    end

    it "coerces a nil pass flag to false" do
      expect(described_class.build(passed: nil)[:passed]).to be(false)
    end

    it "keeps the id and description of a failing example" do
      report = described_class.build(
        passed: false,
        failures: [{ id: "./spec/a_spec.rb[1:1]", description: "A works", message: "boom" }]
      )

      expect(report[:failures]).to eq([{ id: "./spec/a_spec.rb[1:1]", description: "A works", message: "boom" }])
    end

    it "squashes a multi-line message onto its first lines" do
      report = described_class.build(
        passed: false,
        failures: [{ id: "x", description: "d", message: "\nexpected: 1\n     got: 2\n\n(compared using ==)\n# ./a.rb:1" }]
      )

      expect(report[:failures].first[:message]).to eq("expected: 1 got: 2 (compared using ==)")
    end

    it "truncates an overlong message" do
      report = described_class.build(passed: false, failures: [{ id: "x", description: "d", message: "a" * 1000 }])

      message = report[:failures].first[:message]
      expect(message.length).to eq(described_class::MAX_MESSAGE_LENGTH)
      expect(message).to end_with("...")
    end

    it "keeps the head of an overlong message" do
      report = described_class.build(passed: false, failures: [{ id: "x", description: "d", message: "head#{"a" * 1000}" }])

      expect(report[:failures].first[:message]).to start_with("heada")
    end

    it "leaves a message of exactly the maximum length alone" do
      message = "a" * described_class::MAX_MESSAGE_LENGTH

      report = described_class.build(passed: false, failures: [{ id: "x", description: "d", message: message }])

      expect(report[:failures].first[:message]).to eq(message)
    end

    it "turns a missing id or description into an empty string" do
      report = described_class.build(passed: false, failures: [{ id: nil, description: nil, message: "m" }])

      expect(report[:failures]).to eq([{ id: "", description: "", message: "m" }])
    end

    it "stringifies an id that is not a string" do
      report = described_class.build(passed: false, failures: [{ id: :test_x, description: :works, message: "m" }])

      expect(report[:failures]).to eq([{ id: "test_x", description: "works", message: "m" }])
    end

    it "tolerates a failure without a message" do
      report = described_class.build(passed: false, failures: [{ id: "x", description: "d", message: nil }])

      expect(report[:failures].first[:message]).to eq("")
    end

    it "keeps only the first failures but counts all of them" do
      failures = Array.new(described_class::MAX_EXAMPLES + 3) { |i| { id: i.to_s, description: "d", message: "m" } }

      report = described_class.build(passed: false, failures: failures)

      expect(report[:failures].length).to eq(described_class::MAX_EXAMPLES)
      expect(report[:failures].last[:id]).to eq((described_class::MAX_EXAMPLES - 1).to_s)
      expect(report[:failure_count]).to eq(described_class::MAX_EXAMPLES + 3)
    end

    it "keeps the first non-blank lines of an error" do
      error = "\n\nAn error occurred while loading ./spec/a_spec.rb.\n\nNameError:\n  undefined x\n# l1\n# l2\n# l3\n"

      report = described_class.build(passed: false, error: error)

      expect(report[:error]).to eq(
        "An error occurred while loading ./spec/a_spec.rb.\nNameError:\nundefined x\n# l1\n# l2"
      )
    end

    it "truncates each error line on its own" do
      report = described_class.build(passed: false, error: "#{"a" * 1000}\nNameError: nope")

      first, second = report[:error].lines.map(&:chomp)
      expect(first.length).to eq(described_class::MAX_MESSAGE_LENGTH)
      expect(first).to end_with("...")
      expect(second).to eq("NameError: nope")
    end

    it "drops an error that is only whitespace" do
      expect(described_class.build(passed: false, error: " \n \n")[:error]).to be_nil
    end
  end

  describe ".from" do
    it "passes a report hash through" do
      report = described_class.build(passed: false, error: "boom")

      expect(described_class.from(report)).to equal(report)
    end

    it "wraps a true outcome" do
      expect(described_class.from(true)).to eq(described_class.build(passed: true))
    end

    it "wraps a false outcome" do
      expect(described_class.from(false)).to eq(described_class.build(passed: false))
    end

    it "treats a nil outcome as failing" do
      expect(described_class.from(nil)[:passed]).to be(false)
    end
  end
end
