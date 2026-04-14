# frozen_string_literal: true

require "evilution/reporter/html/escape"

RSpec.describe Evilution::Reporter::HTML::Escape do
  describe ".call" do
    it "escapes HTML special characters" do
      expect(described_class.call("<script>&\"'")).to eq("&lt;script&gt;&amp;&quot;&#39;")
    end

    it "coerces nil to empty string" do
      expect(described_class.call(nil)).to eq("")
    end

    it "coerces non-string values via to_s" do
      expect(described_class.call(42)).to eq("42")
    end

    it "returns plain text unchanged" do
      expect(described_class.call("hello world")).to eq("hello world")
    end
  end
end
