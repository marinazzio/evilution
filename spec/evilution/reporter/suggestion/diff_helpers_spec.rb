# frozen_string_literal: true

require "evilution/reporter/suggestion/diff_helpers"

RSpec.describe Evilution::Reporter::Suggestion::DiffHelpers do
  describe ".parse_method_name" do
    it "extracts the method name from an instance method subject" do
      expect(described_class.parse_method_name("Foo#bar")).to eq("bar")
    end

    it "extracts the method name from a class method subject" do
      expect(described_class.parse_method_name("Foo.bar")).to eq("bar")
    end

    it "returns the whole string when there is no separator" do
      expect(described_class.parse_method_name("bar")).to eq("bar")
    end
  end

  describe ".sanitize_method_name" do
    it "removes invalid trailing characters from the sanitized name" do
      expect(described_class.sanitize_method_name("foo?")).to eq("foo")
    end

    it "collapses consecutive underscores" do
      expect(described_class.sanitize_method_name("foo--bar")).to eq("foo_bar")
    end

    it "strips leading and trailing underscores" do
      expect(described_class.sanitize_method_name("?foo?")).to eq("foo")
    end

    it "preserves existing valid identifiers" do
      expect(described_class.sanitize_method_name("already_valid")).to eq("already_valid")
    end
  end
end
